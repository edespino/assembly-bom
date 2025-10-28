# Apache Incubator JAR Naming Issue

## Issue Summary

GeaFlow 0.7.0 build artifacts (JAR files) **do NOT contain "incubating"** in their filenames.

## Examples

All JAR files follow the pattern: `{module}-{version}.jar`

```
❌ geaflow-file-dfs-0.7.0.jar
❌ geaflow-file-common-0.7.0.jar
❌ geaflow-store-rocksdb-0.7.0.jar
❌ geaflow-cluster-0.7.0.jar
```

**Expected naming for incubator projects:**

```
✅ geaflow-file-dfs-0.7.0-incubating.jar
✅ geaflow-file-common-0.7.0-incubating.jar
✅ geaflow-store-rocksdb-0.7.0-incubating.jar
✅ geaflow-cluster-0.7.0-incubating.jar
```

## Apache Incubator Policy

According to the [Apache Incubator Release Checklist](https://cwiki.apache.org/confluence/display/INCUBATOR/Incubator+Release+Checklist):

> "Artifacts require 'incubating' in their names (jar files are **suggested but optional**)"

### Interpretation

- **Source release artifacts** (.tar.gz, .zip on dist.apache.org): **MANDATORY**
- **JAR files and build artifacts**: **SUGGESTED** (strongly recommended but not mandatory)

## Severity Assessment

**Level**: MINOR / SHOULD FIX

While not strictly mandatory for JAR files, best practice for Apache Incubator projects is to include "incubating" in all artifacts to:

1. **Clearly signal project status** to users
2. **Avoid confusion** about maturity level
3. **Follow Apache best practices**
4. **Be consistent** with most other incubator projects

## Impact

- Users downloading JARs might not realize the project is still incubating
- Lack of consistency between source archive naming and built artifact naming
- Could create confusion in dependency management (Maven/Gradle coordinates)

## How to Fix

This typically requires changes to the Maven POM files:

### Option 1: Maven Profiles (Recommended)

Add an incubator profile that modifies the final artifact name:

```xml
<profiles>
  <profile>
    <id>incubating</id>
    <activation>
      <activeByDefault>true</activeByDefault>
    </activation>
    <build>
      <finalName>${project.artifactId}-${project.version}-incubating</finalName>
    </build>
  </profile>
</profiles>
```

### Option 2: Classifier

Add "incubating" as a classifier:

```xml
<build>
  <plugins>
    <plugin>
      <groupId>org.apache.maven.plugins</groupId>
      <artifactId>maven-jar-plugin</artifactId>
      <configuration>
        <classifier>incubating</classifier>
      </configuration>
    </plugin>
  </plugins>
</build>
```

### Option 3: Update Version String

Change the version in all POMs:

```xml
<!-- Current -->
<version>0.7.0</version>

<!-- Updated -->
<version>0.7.0-incubating</version>
```

**Note:** Option 3 is most common and cleanest for incubator projects.

## Examples from Other Incubator Projects

Many Apache Incubator projects include "incubating" in JAR names:

- `apache-toree-0.6.0-incubating-bin.tar.gz`
- `apache-pulsar-2.8.0-incubating-bin.tar.gz`
- `apache-iceberg-0.11.0-incubating.jar`

## Recommendation

**For GeaFlow 0.7.0-rc1 Review:**

Mention this as a **MINOR** issue in the release vote:
- Not a blocker for release (since it's optional for JARs)
- But recommend fixing in next RC or version
- Include in release notes as known issue

**For Release Manager:**

Consider updating Maven configuration to include "incubating" in all artifact names for consistency and clarity.

## Related Issues

This is related to but separate from the **CRITICAL** source archive naming issues:

1. ❌ **CRITICAL**: `apache-geaflow-0.7.0-src.zip` (must be fixed)
2. ❌ **MINOR**: `geaflow-*-0.7.0.jar` (should be fixed)

Both follow the same pattern of missing "incubating" in filenames.

## References

- Apache Incubator Release Checklist: https://cwiki.apache.org/confluence/display/INCUBATOR/Incubator+Release+Checklist
- Apache Incubator Policy: https://incubator.apache.org/policy/incubation.html

---

**Date Identified**: 2025-10-28
**Status**: Documented for review
