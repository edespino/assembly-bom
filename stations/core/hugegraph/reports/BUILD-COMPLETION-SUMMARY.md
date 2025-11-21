# Apache HugeGraph 1.7.0 - Complete Build Report

**Date:** 2025-11-21  
**Validation Framework:** assembly-bom

## Executive Summary

Successfully built **all 4 source distributions** across 3 different build systems (Maven, Python, Go):
- ✅ 3 Maven projects (58 JARs)
- ✅ 1 Python project (2 artifacts)
- ✅ 1 Go project (1 binary)

**Critical Finding:** 59 out of 60 built artifacts (98.3%) are missing "incubating" in their filenames, violating Apache Incubator policy.

---

## Build Results by Project

### 1. apache-hugegraph-incubating-1.7.0-src
**Build System:** Maven (Java 11)  
**Status:** ✅ SUCCESS  
**Artifacts:** 39 JAR files  
**Build Time:** ~10 minutes  
**Command:** `mvn clean install -DskipTests`

**Naming Compliance:** 38/39 violations (only `apache-hugegraph-loader-incubating-1.7.0-shaded.jar` is compliant)

**Key JAR violations:**
- hugegraph-core-1.7.0.jar
- hg-pd-client-1.7.0.jar
- hugegraph-server-1.7.0.jar
- hugegraph-api-1.7.0.jar
- _(35 more JARs with same issue)_

---

### 2. apache-hugegraph-toolchain-incubating-1.7.0-src
**Build System:** Maven (Java 11)  
**Status:** ✅ SUCCESS  
**Artifacts:** 10 JAR files  
**Build Time:** ~30 seconds  
**Command:** `mvn clean install -DskipTests`

**Naming Compliance:** 10/10 violations

**Key JAR violations:**
- hugegraph-loader-1.7.0.jar
- hugegraph-hubble-1.7.0.jar
- hugegraph-tools-1.7.0.jar
- hugegraph-client-1.7.0.jar
- _(6 more JARs with same issue)_

---

### 3. apache-hugegraph-computer-incubating-1.7.0-src

This project contains **two separate sub-projects**:

#### 3a. computer/ (Maven)
**Build System:** Maven (Java 11)  
**Status:** ✅ SUCCESS  
**Artifacts:** 9 JAR files  
**Build Time:** ~37 seconds  
**Command:** `mvn clean install -DskipTests`  
**Location:** `computer/` subdirectory

**Naming Compliance:** 9/9 violations

**All JAR violations:**
- computer-algorithm-1.7.0.jar
- computer-api-1.7.0.jar
- computer-core-1.7.0.jar
- computer-dist-1.7.0.jar
- computer-driver-1.7.0.jar
- computer-k8s-1.7.0.jar
- computer-test-1.7.0.jar
- computer-yarn-1.7.0.jar
- hugegraph-computer-operator-1.7.0.jar

**Root Cause:** Uses `<revision>1.7.0</revision>` property instead of `<revision>1.7.0-incubating</revision>`

#### 3b. vermeer/ (Go)
**Build System:** Go 1.25.2  
**Status:** ✅ SUCCESS  
**Artifacts:** 1 binary (vermeer, 62MB)  
**Build Time:** ~3 seconds  
**Commands:**
```bash
make init        # Download dependencies (supervisord, protoc)
make all         # Generate assets + build
```

**Build Notes:**
- Required dependency update: `sonic` 1.13.2 → 1.14.2 for Go 1.25 compatibility
- Go binaries are not subject to "incubating" filename requirements

---

### 4. apache-hugegraph-ai-incubating-1.7.0-src
**Build System:** Python 3.9 with `pyproject.toml`  
**Status:** ✅ SUCCESS  
**Artifacts:**
- 1 wheel file: `hugegraph_ai-1.7.0-py3-none-any.whl`
- 1 source distribution: `hugegraph_ai-1.7.0.tar.gz`

**Build Time:** ~7 seconds  
**Command:** `python3 -m build`

**Naming Compliance:** 2/2 violations

**Python violations:**
- hugegraph_ai-1.7.0-py3-none-any.whl → should be `hugegraph_ai-1.7.0.incubating-py3-none-any.whl`
- hugegraph_ai-1.7.0.tar.gz → should be `hugegraph_ai-1.7.0.incubating.tar.gz`

**Root Cause:** `pyproject.toml` uses `version = "1.7.0"` instead of `version = "1.7.0.incubating"`

---

## Overall Validation Statistics

| Metric | Count | Percentage |
|--------|-------|------------|
| **Total artifacts validated** | 60 | 100% |
| JAR files (Maven) | 58 | 96.7% |
| Python wheels | 1 | 1.7% |
| Python source distributions | 1 | 1.7% |
| **Compliant artifacts** | **1** | **1.7%** |
| **Non-compliant artifacts** | **59** | **98.3%** |

### Breakdown by Project:
- apache-hugegraph-incubating: 38/39 violations (97.4% non-compliant)
- apache-hugegraph-toolchain: 10/10 violations (100% non-compliant)
- apache-hugegraph-computer/computer: 9/9 violations (100% non-compliant)
- apache-hugegraph-ai: 2/2 violations (100% non-compliant)

---

## Build System Requirements

### Java/Maven Projects
- **Java Version:** Java 11 (OpenJDK 11.0.25) **REQUIRED**
  - Java 8 will fail with "class file has wrong version 55.0" error
- **Maven:** 3.6+ (uses Maven wrapper `./mvnw` when available)
- **Environment:**
  ```bash
  export JAVA_HOME="/usr/lib/jvm/java-11-openjdk-11.0.25.0.9-7.el9.x86_64"
  export PATH="$JAVA_HOME/bin:$PATH"
  ```

### Python Projects
- **Python Version:** Python 3.9+
- **Build Tool:** `python3 -m build` (requires `build` package)
- **Installation:** `pip3 install --user build`

### Go Projects
- **Go Version:** Go 1.23+ (tested with Go 1.25.2)
- **Build Tool:** `make`
- **Dependencies:** 
  - curl and unzip (for downloading supervisord, protoc)
  - Internet connection for first-time setup

---

## Required Fixes for Compliance

### For Maven Projects (58 JARs):
1. **apache-hugegraph-incubating:**
   - Update `pom.xml`: `<version>1.7.0-incubating</version>`
   - Ensure all 39 modules inherit the version

2. **apache-hugegraph-toolchain:**
   - Update root `pom.xml`: `<version>1.7.0-incubating</version>`
   - Propagate to all 10 modules

3. **apache-hugegraph-computer/computer:**
   - Update `pom.xml`: `<revision>1.7.0-incubating</revision>`
   - Affects all 9 computer modules

**Rebuild command:** `mvn clean install -DskipTests`

### For Python Project (2 artifacts):
- Update `pyproject.toml`:
  ```toml
  [project]
  version = "1.7.0.incubating"
  ```
- **Rebuild:** `python3 -m build`

---

## Validation Framework Enhancements Delivered

### New Build Scripts Created:
1. ✅ `stations/core/hugegraph/build.sh`
   - Multi-project Maven build support
   - Java 11 environment configuration
   - Automatic project detection (Maven/Python/Go)

2. ✅ `stations/core/hugegraph/build-python.sh`
   - Python wheel and source distribution generation
   - Auto-installs `build` module if missing
   - Multi-directory support

### Enhanced Generic Scripts:
3. ✅ `stations/generic/apache-validate-build-artifacts.sh`
   - **Multi-language support:** Java (JARs) + Python (wheels, sdist)
   - **Multi-directory validation:** Processes all source directories
   - **Build system auto-detection:** Maven, Python, Go
   - **Comprehensive reporting:** Language-specific fix instructions

4. ✅ `stations/generic/apache-validate-release-structure.sh`
   - RC designation validation
   - Multi-tarball detection
   - Blocks pipeline on policy violations

5. ✅ `stations/generic/apache-rat.sh`
   - Multi-directory RAT analysis
   - Build system detection
   - Aggregated statistics

6. ✅ `stations/generic/apache-validate-compliance.sh`
   - Multi-directory validation
   - Reporting mode (exit 0)

---

## Three Critical Policy Violations

### 1. Missing RC Designation in Release URL
**Current:** `https://dist.apache.org/repos/dist/dev/incubator/hugegraph/1.7.0`  
**Required:** `https://dist.apache.org/repos/dist/dev/incubator/hugegraph/1.7.0-rc1`

### 2. Multiple Repositories Bundled in Single Vote
- 4 source tarballs in one release vote (violates Apache release independence)
- Should be 4 separate votes, one per repository

### 3. Built Artifacts Missing 'incubating' in Filenames
- **59 out of 60 artifacts incorrectly named (98.3% non-compliant)**
- Affects all Maven projects (57 JARs) and Python project (2 artifacts)
- Violates Apache Incubator naming requirements

---

## Vote Recommendation

**-1 (binding/non-binding as appropriate)**

This release cannot proceed due to fundamental Apache policy violations requiring:
1. Release process restructuring (separate votes per repository)
2. URL correction (add RC designation)
3. Complete rebuild with "incubating" versions (all 4 projects)

---

## References

- **Apache Incubator Policy:** https://incubator.apache.org/policy/incubation.html
- **Apache Release Policy:** https://www.apache.org/legal/release-policy.html
- **Detailed Reports:**
  - `hugegraph-final-report.txt` - Executive summary
  - `hugegraph-compliance-summary.txt` - Policy violations
  - `hugegraph-build-summary.txt` - Build results

---

**Generated by:** assembly-bom validation framework  
**Report Location:** `/home/cbadmin/assembly-bom/stations/core/hugegraph/reports/`
