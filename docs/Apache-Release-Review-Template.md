# Apache Incubator Source Release Review Template

**Project:** [Project Name]
**Version:** [Version]
**Release Candidate:** [RC Number]
**Reviewer:** [Your Name]
**Date:** [Date]
**Vote Thread:** [Link to dev@/general@ mailing list thread]

## Release Artifacts

- [ ] Source release tarball downloaded and verified
- [ ] Binary release downloaded and verified (if applicable)
- [ ] Checksums verified (SHA512)
- [ ] PGP signatures verified
- [ ] KEYS file accessible at downloads.apache.org

**Source Tarball:**
**Signature:**
**Checksum:**

## License Compliance Review

### Source Files

- [ ] All source files have proper Apache license headers
- [ ] No Category-X licenses present in source
- [ ] Ran automated license scan (Apache RAT or similar)
- [ ] RAT report shows no issues (or issues documented below)

**RAT Results:**

### Third-Party Code

- [ ] Searched for "derived from", "based on", "adapted from" comments
- [ ] Found all non-ASF copyright statements
- [ ] All third-party code properly attributed in LICENSE file
- [ ] No files with duplicate/redundant license headers

**Non-ASF Code Found:**
```
[List files and their origins]
```

**LICENSE File Coverage:**
- [ ] All third-party components mentioned
- [ ] Copyright holders properly attributed
- [ ] License text included or referenced

### Assembly/Uber JAR Review (if present)

- [ ] Identified all assembly/uber/fat JARs in distribution
- [ ] Extracted and reviewed META-INF folder
- [ ] Listed all bundled third-party packages
- [ ] Verified licenses for all bundled dependencies

**Assembly JARs Found:**
```
[List assembly JARs]
```

**Bundled Libraries:**
| Library | Version | License | Documented in LICENSE? | Documented in NOTICE? |
|---------|---------|---------|------------------------|----------------------|
|         |         |         | [ ]                    | [ ]                  |

**Missing Licenses:**
```
[List any libraries whose licenses are not properly included]
```

### NOTICE File

- [ ] NOTICE file exists in root directory
- [ ] Contains required Apache boilerplate
- [ ] Includes all required third-party attributions
- [ ] Bundled Apache components properly listed

### DISCLAIMER File (Incubator projects only)

- [ ] DISCLAIMER file present
- [ ] Contains standard Apache Incubator disclaimer text

## Build Verification

- [ ] Build succeeds from source tarball
- [ ] All tests pass
- [ ] No git repository required for basic build
- [ ] Build instructions are clear and accurate

**Build Command Used:**
```bash
[Command]
```

**Build Results:**
```
[Summary of build output]
```

**Test Results:**
```
Tests run: [N]
Passed: [N]
Failed: [N]
```

## Source Release Quality

### Required Files

- [ ] LICENSE file present and complete
- [ ] NOTICE file present and complete
- [ ] DISCLAIMER file present (incubator only)
- [ ] README or README.md with basic project info
- [ ] RELEASE_NOTES or CHANGELOG

### Forbidden Content

- [ ] No compiled binaries (.jar, .class, .so, .dll, .exe)
- [ ] No compiled JavaScript/CSS (unless source also included)
- [ ] No convenience binaries without proper source
- [ ] No cryptographic keys or passwords
- [ ] No large data files (should be separate download)

### Best Practices

- [ ] Source tarball follows naming convention (apache-projectname-version-src.tar.gz)
- [ ] Top-level directory matches tarball name (without .tar.gz)
- [ ] No .git directory or other SCM metadata
- [ ] File permissions are reasonable
- [ ] No empty directories (unless needed)

## Makefile/Build System Review

### Git Dependencies

- [ ] Verified which make targets require git repository
- [ ] Targets like `make release`, `make dist`, `make src-release` checked
- [ ] Build succeeds without git repository for source release

**Git-Dependent Targets:**
```
[List targets that inappropriately require git]
```

### Docker Dependencies

- [ ] Identified targets that use Docker
- [ ] Checked if Docker commands create root-owned files
- [ ] Verified clean targets can remove Docker-created artifacts

**Issues Found:**
```
[Document any permission or cleanup issues]
```

## Cryptography

- [ ] Project includes cryptographic functionality (if any)
- [ ] Export notification filed (if required)
- [ ] Documented in README or NOTICE

## Branding

- [ ] Project name follows Apache branding guidelines
- [ ] No unauthorized use of Apache trademark
- [ ] Incubator branding present if applicable (name includes "incubating")

## Issues Identified

### Critical Issues (Release Blocking)

**Issue 1:** [Title]
- **Severity:** Critical
- **Description:**
- **Impact:**
- **Recommendation:**

### Major Issues

**Issue 1:** [Title]
- **Severity:** Major
- **Description:**
- **Impact:**
- **Recommendation:**

### Minor Issues

**Issue 1:** [Title]
- **Severity:** Minor
- **Description:**
- **Impact:**
- **Recommendation:**

## Vote Recommendation

Based on this review:

```
[ ] +1 approve the release
[ ] +0 no opinion
[ ] -1 do not release (must provide justification)
```

**Justification:**

[Explanation of vote]

## Additional Notes

[Any other observations or comments]

## Review Checklist Completion

- [ ] Downloaded and verified all artifacts
- [ ] Ran license compliance script
- [ ] Manually reviewed LICENSE and NOTICE files
- [ ] Built from source
- [ ] Ran tests
- [ ] Reviewed assembly JARs (if present)
- [ ] Checked for git dependencies in build
- [ ] Documented all issues found
- [ ] Completed vote on mailing list

---

## Appendix: Commands Used

### Download and Verify
```bash
# Download artifacts
wget [source tarball URL]
wget [signature URL]
wget [checksum URL]

# Verify signature
gpg --verify [signature] [tarball]

# Verify checksum
sha512sum -c [checksum file]
```

### License Review
```bash
# Run license compliance script
./apache-review-license-compliance.sh

# Manual checks
grep -r "derived from" --include="*.java" --include="*.scala"
grep -r "Copyright (C)" --include="*.java" | grep -v "Apache Software Foundation"
```

### Build and Test
```bash
# Build commands
[Commands used]

# Test commands
[Commands used]
```

### Assembly JAR Review
```bash
# List assembly JAR contents
unzip -l [assembly jar] > assembly-contents.txt

# Extract META-INF
unzip [assembly jar] 'META-INF/*' -d extracted/

# List packages
unzip -l [assembly jar] | grep "\.class$" | awk '{print $4}' | cut -d/ -f1-3 | sort -u
```

---

**Review completed:** [Date]
**Time spent:** [Hours]
