# UV to Poetry Converter Tutorial

This tutorial provides a step-by-step guide for converting Python projects from **uv** to **Poetry** package management.

## Table of Contents
- [Prerequisites](#prerequisites)
- [Understanding the Conversion](#understanding-the-conversion)
- [Manual Step-by-Step Process](#manual-step-by-step-process)
- [Automated Conversion](#automated-conversion)
- [Verification](#verification)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

Before starting, ensure you have:

1. **Poetry installed** (version 1.2+)
   ```bash
   # Check if poetry is installed
   poetry --version
   
   # If not installed, install via official installer
   curl -sSL https://install.python-poetry.org | python3 -
   
   # Or via Homebrew (macOS)
   brew install poetry
   ```

2. **Python 3.10+** (or whatever your project requires)
   ```bash
   python3 --version
   ```

3. **Git** (to clone repositories)
   ```bash
   git --version
   ```

---

## Understanding the Conversion

### What Changes?

**Files to Modify:**
- `pyproject.toml` - Convert from PEP 621 format to Poetry format

**Files to Remove:**
- `uv.lock` - UV's lock file (will be replaced by `poetry.lock`)
- `.venv/` - Any existing UV virtual environment (optional cleanup)

**Files to Create:**
- `poetry.lock` - Poetry's lock file (generated automatically)

### Key Differences

| Aspect | UV Format | Poetry Format |
|--------|-----------|---------------|
| **Section Header** | `[project]` | `[tool.poetry]` |
| **Dependencies** | `dependencies = [...]` | `[tool.poetry.dependencies]` |
| **Dev Dependencies** | `[dependency-groups]` | `[tool.poetry.group.dev.dependencies]` |
| **Build System** | `uv_build` | `poetry-core` |
| **Scripts** | `[project.scripts]` | `[tool.poetry.scripts]` |
| **Author Format** | `{name = "...", email = "..."}` | `"Name <email>"` |

---

## Manual Step-by-Step Process

### Step 1: Clone and Navigate to Repository

```bash
# Clone the repository
git clone https://github.com/username/project-name.git
cd project-name

# Check current structure
ls -la
```

### Step 2: Backup Original pyproject.toml

```bash
# Create a backup
cp pyproject.toml pyproject.toml.uv-backup
```

### Step 3: Convert pyproject.toml

Open `pyproject.toml` and make the following changes:

#### 3a. Convert Project Metadata Section

**BEFORE (UV format):**
```toml
[project]
name = "my-project"
version = "1.0.0"
description = "My project description"
readme = "README.md"
license = "MIT"
authors = [
    { name = "Author Name", email = "author@example.com" }
]
requires-python = ">=3.10"
keywords = ["keyword1", "keyword2"]
classifiers = [
    "Development Status :: 4 - Beta",
]
```

**AFTER (Poetry format):**
```toml
[tool.poetry]
name = "my-project"
version = "1.0.0"
description = "My project description"
authors = ["Author Name <author@example.com>"]
license = "MIT"
readme = "README.md"
keywords = ["keyword1", "keyword2"]
classifiers = [
    "Development Status :: 4 - Beta",
]
```

**Key Changes:**
- `[project]` → `[tool.poetry]`
- `authors` format changes from dict to string
- `requires-python = ">=3.10"` becomes `python = "^3.10"` (in dependencies section)

#### 3b. Convert URLs Section

**BEFORE:**
```toml
[project.urls]
Homepage = "https://github.com/user/project"
Documentation = "https://docs.example.com"
Repository = "https://github.com/user/project.git"
```

**AFTER:**
```toml
[tool.poetry]
# ... other metadata ...
homepage = "https://github.com/user/project"
documentation = "https://docs.example.com"
repository = "https://github.com/user/project.git"
```

**Key Changes:**
- Move URLs directly into `[tool.poetry]` section
- Use lowercase field names

#### 3c. Add Packages Configuration

If your project has a `src/` layout, add:

```toml
[tool.poetry]
# ... other metadata ...
packages = [{include = "your_package_name", from = "src"}]
```

If your package is in the root directory:

```toml
[tool.poetry]
# ... other metadata ...
packages = [{include = "your_package_name"}]
```

#### 3d. Convert Dependencies

**BEFORE:**
```toml
dependencies = [
    "requests>=2.28.0",
    "numpy>=1.24.0",
    "pandas>=2.0.0",
]
```

**AFTER:**
```toml
[tool.poetry.dependencies]
python = "^3.10"
requests = ">=2.28.0"
numpy = ">=1.24.0"
pandas = ">=2.0.0"
```

**Key Changes:**
- Create `[tool.poetry.dependencies]` section
- Add `python` version requirement
- Each dependency becomes a separate line with `name = "version"`

#### 3e. Convert Development Dependencies

**BEFORE:**
```toml
[dependency-groups]
dev = [
    "pytest>=7.0.0",
    "ruff>=0.14.5",
]
```

**AFTER:**
```toml
[tool.poetry.group.dev.dependencies]
pytest = ">=7.0.0"
ruff = ">=0.14.5"
```

**Key Changes:**
- `[dependency-groups]` → `[tool.poetry.group.dev.dependencies]`
- Convert list format to key-value pairs

#### 3f. Convert Scripts

**BEFORE:**
```toml
[project.scripts]
my-command = "my_package.main:main"
```

**AFTER:**
```toml
[tool.poetry.scripts]
my-command = "my_package.main:main"
```

**Key Changes:**
- `[project.scripts]` → `[tool.poetry.scripts]`
- Entry point format stays the same

#### 3g. Convert Build System

**BEFORE:**
```toml
[build-system]
requires = ["uv_build>=0.8.11,<0.9.0"]
build-backend = "uv_build"

[tool.uv.build-backend]
module-name = "my_package"
```

**AFTER:**
```toml
[build-system]
requires = ["poetry-core"]
build-backend = "poetry.core.masonry.api"
```

**Key Changes:**
- Replace `uv_build` with `poetry-core`
- Remove `[tool.uv.build-backend]` section entirely

### Step 4: Remove UV Lock File

```bash
# Remove UV's lock file
rm uv.lock
```

### Step 5: Clean Up Old Virtual Environment (Optional)

```bash
# If UV created a .venv in the project
rm -rf .venv

# Or deactivate if currently active
deactivate 2>/dev/null || true
```

### Step 6: Initialize Poetry

```bash
# Install dependencies and create poetry.lock
poetry install

# This will:
# 1. Create a new virtual environment
# 2. Resolve all dependencies
# 3. Generate poetry.lock
# 4. Install all packages
```

### Step 7: Verify the Conversion

```bash
# Check poetry environment
poetry env info

# List installed packages
poetry show

# If your project has a CLI command, test it
poetry run your-command --help

# Or activate the virtual environment
poetry shell
```

---

## Automated Conversion

See the included scripts:
- **Bash**: `convert-uv-to-poetry.sh`
- **Python**: `convert-uv-to-poetry.py`

Usage:
```bash
# Bash script
./convert-uv-to-poetry.sh /path/to/project

# Python script
python3 convert-uv-to-poetry.py /path/to/project
```

---

## Verification

### Checklist

After conversion, verify:

- [ ] `pyproject.toml` has `[tool.poetry]` section
- [ ] `poetry.lock` exists
- [ ] `uv.lock` has been removed
- [ ] Virtual environment is created: `poetry env info`
- [ ] All dependencies are installed: `poetry show`
- [ ] CLI commands work: `poetry run <command> --help`
- [ ] Project can be built: `poetry build` (optional)
- [ ] Tests pass: `poetry run pytest` (if applicable)

### Common Commands

```bash
# Install dependencies
poetry install

# Add a new dependency
poetry add requests

# Add a development dependency
poetry add --group dev pytest

# Update dependencies
poetry update

# Run a command in the virtual environment
poetry run python script.py

# Activate the virtual environment
poetry shell

# Build the project
poetry build

# Publish to PyPI
poetry publish
```

---

## Troubleshooting

### Issue: Poetry not found

**Solution:**
```bash
# Add poetry to PATH (add to ~/.zshrc or ~/.bashrc)
export PATH="$HOME/.local/bin:$PATH"

# Reload shell configuration
source ~/.zshrc  # or source ~/.bashrc
```

### Issue: Python version mismatch

**Error:** `The currently activated Python version X.X.X is not supported`

**Solution:**
```bash
# Check available Python versions
ls /usr/local/bin/python* || ls /opt/homebrew/bin/python*

# Tell poetry to use a specific Python version
poetry env use python3.10  # or python3.11, python3.12, etc.

# Then install again
poetry install
```

### Issue: Dependency resolution conflicts

**Error:** `SolverProblemError` or version conflicts

**Solution:**

1. Check version constraints in `pyproject.toml`
2. Relax version constraints if too strict:
   ```toml
   # Instead of:
   numpy = ">=1.24.0,<1.25.0"
   
   # Try:
   numpy = ">=1.24.0"
   ```

3. Update the lock file:
   ```bash
   poetry lock --no-update
   ```

### Issue: Package not found in src/ directory

**Error:** `ModuleNotFoundError` when running commands

**Solution:**

Ensure `packages` is correctly configured in `pyproject.toml`:
```toml
[tool.poetry]
packages = [{include = "your_package_name", from = "src"}]
```

Then reinstall:
```bash
poetry install
```

### Issue: Scripts not working after conversion

**Error:** `command not found` when running `poetry run <command>`

**Solution:**

1. Check `[tool.poetry.scripts]` section in `pyproject.toml`
2. Ensure the entry point is correct:
   ```toml
   [tool.poetry.scripts]
   my-command = "package_name.module:function_name"
   ```
3. Reinstall:
   ```bash
   poetry install
   ```

### Issue: Git conflicts after conversion

If you're working in a shared repository:

```bash
# Add poetry.lock to git
git add poetry.lock pyproject.toml

# Remove uv.lock from git
git rm uv.lock

# Commit the changes
git commit -m "Convert from uv to poetry"

# Update .gitignore if needed
echo "# Poetry" >> .gitignore
echo "__pypackages__/" >> .gitignore
```

---

## Additional Resources

- [Poetry Documentation](https://python-poetry.org/docs/)
- [Poetry Configuration](https://python-poetry.org/docs/configuration/)
- [Poetry Commands Reference](https://python-poetry.org/docs/cli/)
- [Managing Dependencies](https://python-poetry.org/docs/managing-dependencies/)
- [PEP 621 Specification](https://peps.python.org/pep-0621/)

---

## Example: Complete Before/After

### Before (UV)

```toml
[project]
name = "example-project"
version = "1.0.0"
description = "An example project"
readme = "README.md"
license = "MIT"
authors = [
    { name = "John Doe", email = "john@example.com" }
]
requires-python = ">=3.10"
dependencies = [
    "requests>=2.28.0",
    "click>=8.0.0",
]

[dependency-groups]
dev = [
    "pytest>=7.0.0",
]

[project.urls]
Homepage = "https://github.com/user/example"
Repository = "https://github.com/user/example.git"

[project.scripts]
example = "example.cli:main"

[build-system]
requires = ["uv_build>=0.8.11"]
build-backend = "uv_build"

[tool.uv.build-backend]
module-name = "example"
```

### After (Poetry)

```toml
[tool.poetry]
name = "example-project"
version = "1.0.0"
description = "An example project"
authors = ["John Doe <john@example.com>"]
license = "MIT"
readme = "README.md"
homepage = "https://github.com/user/example"
repository = "https://github.com/user/example.git"
packages = [{include = "example"}]

[tool.poetry.dependencies]
python = "^3.10"
requests = ">=2.28.0"
click = ">=8.0.0"

[tool.poetry.group.dev.dependencies]
pytest = ">=7.0.0"

[tool.poetry.scripts]
example = "example.cli:main"

[build-system]
requires = ["poetry-core"]
build-backend = "poetry.core.masonry.api"
```

---

## License

This tutorial is provided as-is for educational purposes.
