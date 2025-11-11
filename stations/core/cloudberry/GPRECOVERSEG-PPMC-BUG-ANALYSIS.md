# Investigation Summary: gprecoverseg PPMC Notice Parsing Error

**Date:** 2025-10-18
**Investigator:** AI Assistant with cbadmin
**Status:** Root cause identified, reproduction pending

---

## Bug Report

User reported `gprecoverseg` failure with the following error:

```
20251017:10:58:21:792595 gprecoverseg:cbdb01:gpadmin-[CRITICAL]:-gprecoverseg failed.
(Reason='invalid literal for int() with base 10: "# --------------------------------------------------------------------\n
# NOTICE from the Apache Cloudberry PPMC\n# --------------------------------------------------------------------\n
# This file u') exiting...
```

The error indicates that `gprecoverseg` attempted to parse a string containing the Apache Cloudberry PPMC notice header as an integer, causing a Python `ValueError`.

---

## Investigation Process

We conducted systematic testing to identify the root cause:

### ✅ Test 1: SSH Command Output (CLEAN)

```bash
ssh sdw1 "echo 12345"
# Output: 12345 (no contamination)

ssh -t sdw1 "echo 12345"
# Output: 12345 (no contamination)
```

**Result:** SSH is NOT the contamination vector. The `.bashrc` interactive check prevents `greenplum_path.sh` from executing during non-interactive SSH sessions.

### ✅ Test 2: Configuration Files in Segment Data Directories (CLEAN)

```bash
for host in cdw sdw1 sdw2 sdw3 sdw4; do
    ssh $host "find /data* -type f \( -name '*.conf' -o -name '*.opts' \) | \
    xargs grep -l 'NOTICE from the Apache Cloudberry PPMC' 2>/dev/null"
done
```

**Result:** No contaminated files found in segment data directories on a clean installation.

### 📋 Analysis of `.bashrc` Protection

All segment hosts have this protection in `.bashrc`:

```bash
# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# ... later ...
if [ -f /usr/local/cloudberry/greenplum_path.sh ]; then
  source /usr/local/cloudberry/greenplum_path.sh
fi
```

This prevents `greenplum_path.sh` from executing during non-interactive SSH, which is why the bug cannot be reproduced on clean systems.

### 📄 PPMC Notice Content in greenplum_path.sh

When sourced in an interactive shell, `greenplum_path.sh` prints:

```bash
# --------------------------------------------------------------------
# NOTICE from the Apache Cloudberry PPMC
# --------------------------------------------------------------------
# This file uses the term 'greenplum' to maintain compatibility with
# earlier versions of Apache Cloudberry, which was originally called
# Greenplum. This usage does not refer to VMware Tanzu Greenplum,
# nor does it imply that Apache Cloudberry (Incubating) is affiliated
# with, endorsed by, or sponsored by Broadcom Inc.
#
# This file will be renamed in a future Apache Cloudberry release to
# ensure compliance with Apache Software Foundation guidelines.
# We will announce the change on the project mailing list and website.
#
# See: https://lists.apache.org/thread/b8o974mnnqk6zpy86dgll2pgqcvqgnwm
# --------------------------------------------------------------------
```

---

## Root Cause Analysis

Based on the error message and investigation, the bug occurs when:

1. **gprecoverseg reads a file** that should contain numeric data (PID, port, dbid, etc.)
2. **That file has been contaminated** with the PPMC notice header text
3. **Python attempts `int(file_content)`** and raises `ValueError`

The contamination likely occurred during one of these scenarios:

### Scenario A: Version Upgrade with Script Output Redirection

```bash
# During cluster upgrade or reconfiguration
source /usr/local/cloudberry/greenplum_path.sh  # PPMC notice prints to stdout
some_command_that_generates_config > /data/primary/gpseg7/some_file
# PPMC notice gets written into the file
```

### Scenario B: Custom Wrapper Scripts

A wrapper script that sources `greenplum_path.sh` with stdout redirected:

```bash
#!/bin/bash
source /usr/local/cloudberry/greenplum_path.sh > recovery_config.txt
# PPMC notice becomes first lines of recovery_config.txt
```

### Scenario C: Earlier greenplum_path.sh Versions

Earlier versions of `greenplum_path.sh` may have:
- Printed to stdout unconditionally (not checking for interactive shells)
- Printed before the interactive check in certain initialization scenarios
- Been sourced from `/etc/profile` or `/etc/bash.bashrc` (runs before `.bashrc` protection)

### Scenario D: Interactive Session Output Capture

Running commands in an interactive shell with output redirection:

```bash
# User logs in interactively (PPMC notice displays)
$ psql -c "SELECT some_config" > segment_config.txt
# If greenplum_path.sh is sourced in the session, notice might be captured
```

---

## Why This Bug is Hard to Reproduce

**On clean, newly-initialized clusters:**
- ✅ `.bashrc` interactive check prevents PPMC notice during SSH
- ✅ No contaminated files exist in data directories
- ✅ `greenplum_path.sh` notice is properly isolated from command output

**The bug only affects systems where:**
- ❌ Cluster was initialized/upgraded during a transition period with a different `greenplum_path.sh` behavior
- ❌ Custom scripts source `greenplum_path.sh` with redirected stdout
- ❌ Files were written during an interactive session that captured the notice
- ❌ `/etc/profile` or `/etc/bash.bashrc` sources `greenplum_path.sh` globally

---

## Potential Files That Could Be Contaminated

Based on the error context (`/u00/cbdb/primary/gpseg7`), candidate files include:

1. **Recovery metadata files** - gprecoverseg-specific configuration
2. **`postmaster.opts`** - May be parsed for port numbers
3. **`postgresql.auto.conf`** - Auto-generated configuration
4. **`internal.auto.conf`** - Internal Cloudberry settings
5. **Custom recovery tracking files** - Created during previous recovery attempts
6. **`postmaster.pid`** - Process ID file (expects integer on first line)
7. **Temporary recovery state files** - Created during gprecoverseg operations

---

## Recommendations

### For Users Experiencing This Bug

#### 1. Identify contaminated files

```bash
# On affected segment host
grep -r "NOTICE from the Apache Cloudberry PPMC" /u00/cbdb/primary/gpseg7/

# Or search across all segment data directories
for host in cdw sdw1 sdw2 sdw3 sdw4; do
    echo "=== Checking $host ==="
    ssh $host "grep -r 'NOTICE from the Apache Cloudberry PPMC' /data*/primary /data*/mirror 2>/dev/null | head -10"
done
```

#### 2. Clean the contaminated files

- **Option A:** Remove the PPMC notice header lines manually
  ```bash
  # Edit the file and remove lines starting with "# ----" and "# NOTICE"
  vi /path/to/contaminated/file
  ```

- **Option B:** Restore from backup if available
  ```bash
  cp /path/to/backup/file /path/to/contaminated/file
  ```

- **Option C:** Reinitialize the segment if necessary
  ```bash
  gprecoverseg -a
  ```

#### 3. Prevent recurrence

- Audit custom scripts that source `greenplum_path.sh`
- Ensure stdout redirection doesn't capture notice text
- Check `/etc/profile`, `/etc/bash.bashrc` for unsafe sourcing
- Remove `greenplum_path.sh` sourcing from global profile files

### For Cloudberry Development Team

#### 1. Fix `greenplum_path.sh` to NEVER print to stdout

**Option A: Print to stderr**
```bash
# Print notice to stderr instead of stdout
echo "# --------------------------------------------------------------------" >&2
echo "# NOTICE from the Apache Cloudberry PPMC" >&2
echo "# --------------------------------------------------------------------" >&2
# ... rest of notice ...
```

**Option B: Only show in truly interactive terminals**
```bash
# Only show in truly interactive shells with a terminal
if [[ $- == *i* ]] && [[ -t 0 ]]; then
    echo "# --------------------------------------------------------------------"
    echo "# NOTICE from the Apache Cloudberry PPMC"
    echo "# --------------------------------------------------------------------"
    # ... rest of notice ...
fi
```

**Option C: Show once per session**
```bash
# Use environment variable to show only once
if [[ -z "${CLOUDBERRY_NOTICE_SHOWN:-}" ]] && [[ $- == *i* ]]; then
    export CLOUDBERRY_NOTICE_SHOWN=1
    echo "# --------------------------------------------------------------------"
    echo "# NOTICE from the Apache Cloudberry PPMC"
    echo "# --------------------------------------------------------------------"
    # ... rest of notice ...
fi
```

#### 2. Add input validation in gprecoverseg

```python
# Before:
value = int(file_content)

# After:
content = file_content.strip()
if not content.isdigit():
    logger.error(f"Expected numeric value in file {filename}, got: {content[:100]}")
    raise ValueError(f"File {filename} contains non-numeric data. "
                     f"File may be corrupted or contaminated. "
                     f"First 100 chars: {content[:100]}")
value = int(content)
```

#### 3. Add file content checks during recovery

- Detect unexpected content in configuration files
- Provide clear error messages about contamination
- Auto-clean known contamination patterns (e.g., PPMC notice header)

```python
def sanitize_config_file(filepath):
    """Remove known contamination patterns from config files."""
    with open(filepath, 'r') as f:
        lines = f.readlines()

    # Filter out PPMC notice lines
    clean_lines = [
        line for line in lines
        if not line.strip().startswith('# NOTICE from the Apache Cloudberry PPMC')
        and not line.strip().startswith('# --------------------------------------------------------------------')
    ]

    with open(filepath, 'w') as f:
        f.writelines(clean_lines)
```

#### 4. Document the issue

- Add to upgrade notes
- Include in troubleshooting guide
- Warn about stdout redirection with `greenplum_path.sh`
- Add to known issues in release notes

---

## Verification Needed

To fully confirm the root cause, we need:

1. **Access to the affected system** to examine contaminated files
   - Specific file path that gprecoverseg was trying to parse
   - Full contents of the contaminated file

2. **gprecoverseg source code review** to identify exactly which file it's parsing
   - Location in Python code where `int()` conversion fails
   - What the code expects to find in that file

3. **Version history** of when the PPMC notice was added to `greenplum_path.sh`
   - Was there a version that printed to stdout unconditionally?
   - When was the interactive check added?

4. **Reproduction test case**
   - Systematically contaminate candidate files
   - Run gprecoverseg to identify which file triggers the bug
   - Document exact reproduction steps

---

## Related Issues

This is similar to issues seen in other database systems where:
- Shell scripts print banners/notices to stdout
- Tools parse command output expecting clean numeric values
- SSH wrappers or automation scripts get contaminated output

### Examples from Other Projects

- **PostgreSQL:** `pg_ctl` carefully avoids printing non-essential output
- **MySQL:** Startup messages go to error log, not stdout
- **Redis:** Banner only shown in interactive mode

**Best Practice:** Shell scripts that are sourced should NEVER print to stdout unless that's their explicit purpose (e.g., `echo $VARIABLE` in getter scripts).

---

## Test Environment Details

**Our test environment (clean, cannot reproduce):**
- Cloudberry Database Version: postgres (Apache Cloudberry) 2.0.0-incubating build dev
- OS: Debian GNU/Linux 12 (bookworm)
- Cluster: Multinode (1 coordinator: cdw, 4 segment hosts: sdw1-sdw4)
- Installation path: `/usr/local/cloudberry`
- Data directories: `/data1-4/primary`, `/data1-4/mirror`

**Original affected environment:**
- User: `gpadmin@cbdb01`
- Segment path: `/u00/cbdb/primary/gpseg7`
- Error timestamp: 2025-10-17 10:58:21

---

## Next Steps

1. ✅ Document investigation findings (this file)
2. ⏳ Request access to affected system or contaminated files
3. ⏳ Review gprecoverseg Python source code
4. ⏳ Create reproduction test script
5. ⏳ Submit upstream bug report to Apache Cloudberry
6. ⏳ Propose patch to fix `greenplum_path.sh`

---

## References

- Original error report: User-provided log snippet
- Cloudberry PPMC Notice: https://lists.apache.org/thread/b8o974mnnqk6zpy86dgll2pgqcvqgnwm
- Related test script: `stations/core/cloudberry/gprecoverseg-test.sh`
- Related test script: `stations/core/cloudberry/gprecoverseg-multinode-test.sh`
