# Apache Toree 0.6.0-incubating RC1 - Source Review

**Date:** 2025-10-26
**Reviewer:** [Your Name]
**Artifact:** apache-toree-0.6.0-incubating-src

## Executive Summary

This review identifies issues in the build system that affect source release distributions. The primary concerns involve:
- Git dependencies in Makefile targets that are inappropriate for source releases
- Root-owned artifacts from Docker builds that cannot be cleaned
- Bugs in the check-licenses script (already addressed via PR)
- Lack of proper guards for git-dependent operations

## Issues Identified

### Issue 1: Git Dependencies in Release Targets

**Severity:** High
**Affected Targets:** `make release`, `make src-release`, `make dist`, `make pip-release`

**Description:**
Several Makefile targets have hard dependencies on git that make them inappropriate for execution in a source release directory (which is not a git repository).

**Evidence:**

1. **Line 25** - COMMIT variable requires git:
   ```makefile
   COMMIT=$(shell git rev-parse --short=12 --verify HEAD)
   ```

2. **Line 304** - `src-release` target explicitly uses git archive:
   ```makefile
   dist/toree-src/toree-$(VERSION)-src.tar.gz:
       @mkdir -p dist/toree-src
       @git archive HEAD --prefix toree-$(VERSION)-src/ -o dist/toree-src/toree-$(VERSION)-src.tar.gz
   ```

3. **Lines 239, 255** - Pip packages embed COMMIT in version files:
   ```makefile
   printf "__commit__ = '$(COMMIT)'\n" >> dist/toree-pip/toree/_version.py
   printf "__commit__ = '$(COMMIT)'\n" >> dist/apache-toree-pip/toree/_version.py
   ```

4. **Line 143** - VERSION file includes COMMIT:
   ```makefile
   @echo "COMMIT: $(COMMIT)" >> dist/toree/VERSION
   ```

**Impact:**
- `make release` will fail when attempting `src-release` due to missing git
- `make dist` and `make pip-release` will execute but produce artifacts with empty/invalid COMMIT values
- Error messages are confusing and don't clearly indicate the root cause
- Users of source releases may attempt these targets expecting them to work

**Recommendation:**
Add git repository detection to targets that require git:
```makefile
.require-git:
	@test -d .git || (echo "ERROR: This command requires a git repository and should not be run from a source release" && exit 1)

release: .require-git pip-release src-release bin-release sign
src-release: .require-git dist/toree-src/toree-$(VERSION)-src.tar.gz
dist: .require-git dist/toree pip-release
pip-release: .require-git dist/toree-pip/toree-$(BASE_VERSION).tar.gz ...
```

---

### Issue 2: Root-Owned Artifacts from Docker Builds

**Severity:** Medium
**Affected Targets:** `make pip-release`, `make system-test`, `make clean`

**Description:**
Docker commands that run as root create artifacts owned by root in the dist/ directory. These cannot be cleaned up by normal users running `make clean`.

**Evidence:**

1. **Lines 240-241, 257-258** - Pip package builds run as root:
   ```makefile
   @$(DOCKER) --user=root $(IMAGE) python setup.py sdist --dist-dir=.
   @$(DOCKER) -p 8888:8888 --user=root $(IMAGE) bash -c 'pip install ...'
   ```

2. **Line 210** - System tests run as root:
   ```makefile
   @docker run -t --rm \
       --name jupyter_kernel_tests \
       ...
       --user=root \
       $(TOREE_DEV_IMAGE) \
   ```

3. **Line 73** - Clean command cannot remove root-owned files:
   ```makefile
   clean-dist:
       -rm -fr dist
   ```

**Impact:**
- After running `make pip-release` or `make system-test`, dist/ contains root-owned files
- Regular users cannot run `make clean` successfully
- Users must manually use `sudo rm -rf dist` to clean up
- Repeated builds may fail due to permission conflicts with existing root-owned files
- Development workflow is interrupted

**Recommendation:**
Options to fix:
1. Run Docker commands as current user: `--user=$(id -u):$(id -g)`
2. Add a docker-based clean target: `docker run --user=root -v pwd:/srv/toree --rm alpine rm -rf /srv/toree/dist`
3. Document that `sudo make clean` is required after Docker-based builds
4. Chown files back to user after Docker operations complete

---

### Issue 3: Non-Idempotent clean-dist Target

**Severity:** Low
**Affected Targets:** `make clean-dist`

**Description:**
While the `-rm -fr dist` command uses `-` to ignore errors, it's not truly idempotent and will show error messages if dist/ doesn't exist on first run.

**Evidence:**
```makefile
clean-dist:
    -rm -fr dist
```

**Impact:**
Minor - confusing error message on first clean, but does not cause build failures.

**Recommendation:**
Use idempotent form:
```makefile
clean-dist:
    @rm -rf dist 2>/dev/null || true
```
or
```makefile
clean-dist:
    @test -d dist && rm -rf dist || true
```

---

### Issue 4: Bugs in check-licenses Script

**Severity:** Medium
**Affected Files:** `etc/tools/check-licenses`
**Status:** Fixed in PR (commit d9ae44d659330b16917de4f247f4b1416e2cfb5e)

**Description:**
The check-licenses script contained two bugs that would cause failures when running license audits, particularly on clean checkouts.

**Evidence:**

1. **Line 63** - Unnecessary and buggy mkdir command:
   ```bash
   mkdir -p "$FWDIR"etc/tools/
   ```
   Issues:
   - The `etc/tools/` directory already exists in the repository (contains this script)
   - Missing path separator between `"$FWDIR"` and `etc/tools/`
   - Would create a phantom directory like `toree-0.6.0-incubating-srcetc` in the parent directory
   - Unnecessary operation that added no value

2. **Missing target directory creation:**
   - Script writes to `target/rat-results.txt` without ensuring target/ exists
   - Fails on clean checkouts where no build has been run
   - User must run `make build` first just to create the directory

**Impact:**
- `make audit-licenses` fails on clean source releases or fresh git clones
- Creates confusing phantom directories in parent directory tree
- Adds unnecessary prerequisite of running a build before running license checks
- License audit cannot be performed independently

**Resolution:**
Pull request created to fix both issues:
- **PR:** https://github.com/apache/incubator-toree/pull/233
- **Branch:** `fix-check-licenses-script`
- **Commit:** d9ae44d659330b16917de4f247f4b1416e2cfb5e
- **Author:** Ed Espino <espino@apache.org>
- **Date:** 2025-10-26

Changes made:
1. Removed the buggy `mkdir -p "$FWDIR"etc/tools/` line
2. Added `mkdir -p target` before writing rat-results.txt

**Recommendation:**
Merge PR #233 to resolve these issues before the final release.

---

## Summary of Recommendations

1. **High Priority:** Add `.require-git` guards to git-dependent targets
2. **Medium Priority:** Fix Docker user permissions to avoid root-owned artifacts
3. **Medium Priority:** Merge fix-check-licenses-script PR (already addressed)
4. **Low Priority:** Make clean-dist truly idempotent
5. **Documentation:** Update README/BUILD instructions to clarify which targets are for git repositories vs. source releases

## Targets Safe for Source Releases

The following targets have been verified to work correctly from source releases:
- `make build` - Build assembly JARs ✓ **Verified**
- `make test` - Run unit tests ✓ **Verified**
- `make bin-release` - Create binary distribution (with caveat that COMMIT will be empty)

### Test Results

Verified on 2025-10-26 from source release:
```
[info] Run completed in 1 minute, 28 seconds.
[info] Total number of tests run: 235
[info] Suites: completed 42, aborted 0
[info] Tests: succeeded 235, failed 0, canceled 0, ignored 0, pending 0
[info] All tests passed.
```

**Result:** Both `make build` and `make test` complete successfully from the source release tarball, confirming that basic build and test operations do not require a git repository.

## Additional Notes

- The Makefile appears to be designed primarily for development in a git repository
- Source release users should be directed to use `make build` and `make bin-release` only
- Consider providing a separate Makefile.src-release for source distributions with appropriate targets

## Fixes Applied

The following pull requests have been created to address issues found in this review:

### fix-check-licenses-script (PR #233)
- **PR:** https://github.com/apache/incubator-toree/pull/233
- **Branch:** `fix-check-licenses-script` (fork/fix-check-licenses-script)
- **Commit:** d9ae44d659330b16917de4f247f4b1416e2cfb5e
- **Author:** Ed Espino <espino@apache.org>
- **Date:** 2025-10-26 17:53:55 -0700
- **Status:** Pending merge
- **Addresses:** Issue 4 - Bugs in check-licenses script
- **Changes:**
  - Removed buggy `mkdir -p "$FWDIR"etc/tools/` line
  - Added `mkdir -p target` before writing rat-results.txt
  - Ensures license audit can run on clean checkouts
