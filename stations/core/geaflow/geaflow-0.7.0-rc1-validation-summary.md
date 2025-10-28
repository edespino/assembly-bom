# Apache GeaFlow 0.7.0-rc1 Validation Report

**Date**: 2025-10-28  
**Component**: Apache GeaFlow (Incubator)  
**Release**: 0.7.0-rc1  
**Release URL**: https://dist.apache.org/repos/dist/dev/incubator/geaflow/v0.7.0-rc1

## Cryptographic Verification

✅ **GPG Signatures**: PASSED  
✅ **SHA512 Checksums**: PASSED  
✅ **KEYS File**: Successfully imported 6 release keys

All cryptographic signatures and checksums verified correctly.

## Apache Incubator Compliance

❌ **FAILED** - Multiple critical violations of Apache Incubator Policy

### Critical Issues

#### 1. Naming Convention Violations

Per [Apache Incubator Policy](https://incubator.apache.org/policy/incubation.html), release artifacts MUST include "incubating" in filenames.

- ❌ **Artifact name**: `apache-geaflow-0.7.0-src.zip`  
  **Required**: `apache-geaflow-0.7.0-incubating-src.zip`

- ❌ **Directory name**: `apache-geaflow-0.7.0-src/`  
  **Required**: `apache-geaflow-0.7.0-incubating-src/`

#### 2. Missing Required Files

- ❌ **NOTICE**: MISSING (required for all Apache releases)
- ❌ **DISCLAIMER or DISCLAIMER-WIP**: MISSING (required for incubator projects)

### Passing Items

- ✅ **LICENSE**: Present and valid (Apache License 2.0)

## Recommendation

**-1 (binding/non-binding)** - This release does NOT comply with Apache Incubator requirements.

### Required Actions

The release manager must:

1. **Add NOTICE file** with:
   - Apache Software Foundation attribution
   - Copyright notice with current year (2025)

2. **Add DISCLAIMER or DISCLAIMER-WIP file** with incubation status

3. **Rename all artifacts** to include "incubating":
   - `apache-geaflow-0.7.0-src.zip` → `apache-geaflow-0.7.0-incubating-src.zip`

4. **Re-cut the release candidate** as 0.7.0-rc2

## References

- Apache Incubator Policy: https://incubator.apache.org/policy/incubation.html
- Incubator Release Checklist: https://cwiki.apache.org/confluence/display/INCUBATOR/Incubator+Release+Checklist
- Validation Tool: Assembly BOM `apache-validate-compliance.sh`

## Validation Command

```bash
./assemble.sh -b apache-bom.yaml -c geaflow -r
```
