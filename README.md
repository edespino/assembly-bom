# 🔩 Assembly BOM

**Assembly BOM** is a modular, script-driven build orchestration system for multi-component, multi-repository database systems. It uses a declarative `bom.yaml` to define components, tools, and build steps — enabling reproducible, portable builds from source.

---

## 📁 Project Structure

```
assembly-bom/
├── assemble.sh                  # Main orchestrator
├── bom.yaml                     # Bill of Materials (defines components & steps)
├── config/
│   ├── bootstrap.sh             # Toolchain setup (e.g. yq, git)
│   └── env.sh                   # Shared exports (e.g. PARTS_DIR)
├── stations/
│   ├── build-cloudberry.sh     # Custom build for 'cloudberry'
│   ├── build.sh                 # Generic make build
│   ├── clone.sh                 # Generic git clone
│   ├── configure-cloudberry.sh # Custom configure for 'cloudberry'
│   ├── configure.sh             # Generic autotools configure
│   ├── install-cloudberry.sh   # Custom install for 'cloudberry'
│   ├── install.sh               # Generic install
│   └── test.sh                  # Generic test
└── parts/                       # Populated with checked-out source trees
```

---

## ✍️ Example `bom.yaml`

```yaml
products:
  cloudberry:
    components:
      core:
        - name: cloudberry
          url: git@github.com:apache/cloudberry.git
          branch: main
          configure_flags: |
            --enable-gpfdist
            --with-ldap
          steps: [clone, configure, build, install, test]
          test_configs:
            - name: "default"
              pgoptions: ""
              target: "installcheck" 
            - name: "optimizer-off"
              pgoptions: "-c optimizer=off"
              target: "installcheck"

      extensions:
        - name: cloudberry-pxf
          url: git@github.com:apache/cloudberry-pxf.git
          branch: main
          configure_flags: |
            --with-cloudberry-core=/usr/local
          steps: [clone, configure, build, install]
```

---

## ⚙️ How It Works

1. **Declare** components and steps in `bom.yaml`

2. **Run**:

   ```bash
   ./assemble.sh --run
   ```

3. **Customize** behavior with component-specific overrides:

   ```
   stations/configure-cloudberry.sh
   stations/build-cloudberry.sh
   stations/install-cloudberry.sh
   ```

4. **Skip steps** if preconditions are met (e.g., already cloned or configured):

   ```yaml
   steps: [build, install]
   ```

---

## 💠 Requirements

* `bash`
* `yq` (v4+)
* `git`
* Compiler and libraries required by your components

---

## 🧪 Common Commands

### Build specific components
```bash
# Build entire product
./assemble.sh --run

# Build specific component
./assemble.sh --run --component cloudberry

# Build with custom steps
./assemble.sh --run --component cloudberry --steps configure,build,install

# Show component list and build order
./assemble.sh --list
```

### Test configurations
```bash
# Run default installcheck tests
./assemble.sh --run --component cloudberry --steps installcheck

# Run with optimizer disabled
./assemble.sh --run --component cloudberry --steps installcheck --test-config optimizer-off

# Run PAX storage tests
./assemble.sh --run --component cloudberry --steps installcheck --test-config pax-storage
```

### Running individual steps
You can run any step directly:

```bash
NAME=cloudberry INSTALL_PREFIX=/usr/local ./stations/build-cloudberry.sh

# Run with specific test configuration
TEST_CONFIG_NAME=optimizer-off ./stations/installcheck-cloudberry.sh
```

---

## 🔧 Customization

* Per-component logic: `stations/<step>-<name>.sh`
* Shared environment: `config/env.sh`
* Tool bootstrapping: `config/bootstrap.sh`

---

## 📦 License

Apache License 2.0 — see [LICENSE](LICENSE)
