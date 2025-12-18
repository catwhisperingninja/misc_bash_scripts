# UV to Poetry Conversion Tools

This directory contains comprehensive tools and documentation for converting Python projects from **uv** to **Poetry** package management.

## 📚 Files Included

### 1. **UV-to-POETRY-CONVERTER.md** (Tutorial)
A comprehensive step-by-step tutorial covering:
- Prerequisites and setup
- Understanding the conversion process
- Manual conversion instructions with detailed before/after examples
- Verification steps
- Troubleshooting common issues
- Poetry usage guide

**Recommended for:** First-time converters or those who want to understand the process deeply.

### 2. **convert-uv-to-poetry.sh** (Bash Script)
Fully automated bash script for converting projects.

**Features:**
- ✅ Prerequisite checks (Poetry, Python)
- ✅ Automatic pyproject.toml conversion
- ✅ Backup creation
- ✅ UV lock file removal
- ✅ Poetry installation and verification
- ✅ Colored output and progress indicators
- ✅ Interactive prompts for optional steps

**Usage:**
```bash
# Convert current directory
./convert-uv-to-poetry.sh

# Convert specific directory
./convert-uv-to-poetry.sh /path/to/project

# Show help
./convert-uv-to-poetry.sh --help
```

### 3. **convert-uv-to-poetry.py** (Python Script)
Python-based conversion script with the same functionality as the bash script.

**Features:**
- ✅ Cross-platform compatibility
- ✅ Type hints and proper error handling
- ✅ Detailed parsing of pyproject.toml
- ✅ Automatic package structure detection
- ✅ Comprehensive conversion logic

**Usage:**
```bash
# Convert current directory
python3 convert-uv-to-poetry.py

# Convert specific directory
python3 convert-uv-to-poetry.py /path/to/project

# Show help
python3 convert-uv-to-poetry.py --help
```

## 🚀 Quick Start

### For Newly Cloned Repositories

1. **Clone the repository:**
   ```bash
   git clone https://github.com/username/project.git
   cd project
   ```

2. **Choose your conversion method:**

   **Option A: Automated (Bash)**
   ```bash
   ./convert-uv-to-poetry.sh
   ```

   **Option B: Automated (Python)**
   ```bash
   python3 convert-uv-to-poetry.py
   ```

   **Option C: Manual**
   Follow the step-by-step guide in `UV-to-POETRY-CONVERTER.md`

3. **Verify the conversion:**
   ```bash
   poetry env info
   poetry show
   poetry run <your-command> --help
   ```

4. **Commit the changes:**
   ```bash
   git add pyproject.toml poetry.lock
   git rm uv.lock
   git commit -m "Convert from uv to poetry"
   ```

## 🔍 What Gets Changed

### Files Modified:
- ✏️ `pyproject.toml` - Converted from PEP 621/uv format to Poetry format

### Files Created:
- ➕ `poetry.lock` - Poetry's lock file
- ➕ `pyproject.toml.uv-backup` - Backup of original file

### Files Removed:
- ➖ `uv.lock` - UV's lock file
- ➖ `.venv/` - (Optional) UV's virtual environment

## 📋 Prerequisites

Before using any conversion tool, ensure you have:

1. **Poetry** (version 1.2+)
   ```bash
   # Check installation
   poetry --version
   
   # Install if needed (macOS/Linux)
   curl -sSL https://install.python-poetry.org | python3 -
   
   # Or via Homebrew
   brew install poetry
   ```

2. **Python 3.10+**
   ```bash
   python3 --version
   ```

3. **Git** (for cloning repositories)
   ```bash
   git --version
   ```

## 🆚 Script Comparison

| Feature | Bash Script | Python Script | Manual Tutorial |
|---------|-------------|---------------|-----------------|
| **Platform** | Unix/macOS/Linux | Cross-platform | Any |
| **Dependencies** | bash, python3 | python3 | None |
| **Speed** | Fast | Fast | Depends on user |
| **Flexibility** | Medium | High | Very High |
| **Best For** | Unix users | All platforms | Learning/Custom cases |

## 🐛 Troubleshooting

If you encounter issues:

1. **Check the tutorial:** `UV-to-POETRY-CONVERTER.md` has a comprehensive troubleshooting section

2. **Verify prerequisites:**
   ```bash
   poetry --version
   python3 --version
   ```

3. **Review the backup:** If conversion fails, restore from `pyproject.toml.uv-backup`

4. **Manual adjustments:** Sometimes version constraints need manual tweaking

## 💡 Tips

1. **Always review the converted `pyproject.toml`** before committing
2. **Test your project** after conversion: `poetry run <command>`
3. **Keep the backup file** until you're sure everything works
4. **Update your CI/CD** if it references UV commands

## 📖 Additional Resources

- [Poetry Documentation](https://python-poetry.org/docs/)
- [Poetry CLI Reference](https://python-poetry.org/docs/cli/)
- [PEP 621 Specification](https://peps.python.org/pep-0621/)

## 🤝 Contributing

If you find issues or have improvements:
1. Test the conversion tools on various projects
2. Document any edge cases
3. Suggest enhancements

## 📝 License

These conversion tools are provided as-is for educational and practical purposes.

---

**Need help?** Refer to `UV-to-POETRY-CONVERTER.md` for detailed documentation!
