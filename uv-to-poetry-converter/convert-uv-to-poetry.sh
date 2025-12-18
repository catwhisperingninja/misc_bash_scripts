#!/usr/bin/env bash

################################################################################
# UV to Poetry Converter Script (Bash)
# 
# This script automates the conversion of Python projects from uv to Poetry
# package management.
#
# Usage: ./convert-uv-to-poetry.sh [project_directory]
#
# Author: Auto-generated
# License: MIT
################################################################################

set -euo pipefail  # Exit on error, undefined variable, or pipe failure

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_header() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $1"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Main conversion function
convert_uv_to_poetry() {
    local project_dir="${1:-.}"
    
    print_header "UV to Poetry Converter"
    
    # Step 1: Validate prerequisites
    print_info "Checking prerequisites..."
    
    if ! command_exists poetry; then
        print_error "Poetry is not installed"
        echo ""
        echo "Install Poetry using one of these methods:"
        echo "  • Official installer: curl -sSL https://install.python-poetry.org | python3 -"
        echo "  • Homebrew (macOS): brew install poetry"
        echo "  • pipx: pipx install poetry"
        exit 1
    fi
    print_success "Poetry is installed ($(poetry --version))"
    
    if ! command_exists python3; then
        print_error "Python 3 is not installed"
        exit 1
    fi
    print_success "Python 3 is installed ($(python3 --version))"
    
    # Step 2: Navigate to project directory
    print_info "Navigating to project directory: $project_dir"
    cd "$project_dir" || {
        print_error "Cannot access directory: $project_dir"
        exit 1
    }
    print_success "Changed to directory: $(pwd)"
    
    # Step 3: Check for pyproject.toml
    if [[ ! -f "pyproject.toml" ]]; then
        print_error "pyproject.toml not found in $(pwd)"
        exit 1
    fi
    print_success "Found pyproject.toml"
    
    # Step 4: Check if this is a UV project
    if ! grep -q "\[build-system\]" pyproject.toml || ! grep -q "uv" pyproject.toml; then
        print_warning "This doesn't appear to be a UV project"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Conversion cancelled"
            exit 0
        fi
    fi
    
    # Step 5: Backup original pyproject.toml
    print_info "Creating backup of pyproject.toml..."
    cp pyproject.toml pyproject.toml.uv-backup
    print_success "Backup created: pyproject.toml.uv-backup"
    
    # Step 6: Parse and convert pyproject.toml
    print_info "Converting pyproject.toml to Poetry format..."
    
    # Create a Python script to do the conversion
    python3 - <<'EOF'
import re
import sys
from pathlib import Path

def convert_toml():
    pyproject_path = Path("pyproject.toml")
    content = pyproject_path.read_text()
    
    # Extract information from [project] section
    project_section = re.search(r'\[project\](.*?)(?=\n\[|\Z)', content, re.DOTALL)
    if not project_section:
        print("Error: No [project] section found", file=sys.stderr)
        sys.exit(1)
    
    project_content = project_section.group(1)
    
    # Extract fields
    name = re.search(r'name\s*=\s*"([^"]+)"', project_content)
    version = re.search(r'version\s*=\s*"([^"]+)"', project_content)
    description = re.search(r'description\s*=\s*"([^"]+)"', project_content)
    readme = re.search(r'readme\s*=\s*"([^"]+)"', project_content)
    license_match = re.search(r'license\s*=\s*"([^"]+)"', project_content)
    requires_python = re.search(r'requires-python\s*=\s*"([^"]+)"', project_content)
    
    # Extract authors (convert from dict to string format)
    authors_list = []
    authors_section = re.search(r'authors\s*=\s*\[(.*?)\]', project_content, re.DOTALL)
    if authors_section:
        author_dicts = re.findall(r'\{\s*name\s*=\s*"([^"]+)"(?:,\s*email\s*=\s*"([^"]+)")?\s*\}', authors_section.group(1))
        for name_val, email_val in author_dicts:
            if email_val:
                authors_list.append(f'"{name_val} <{email_val}>"')
            else:
                authors_list.append(f'"{name_val}"')
    
    # Extract keywords
    keywords = re.search(r'keywords\s*=\s*(\[.*?\])', project_content, re.DOTALL)
    
    # Extract classifiers
    classifiers = re.search(r'classifiers\s*=\s*(\[.*?\])', project_content, re.DOTALL)
    
    # Extract dependencies
    dependencies = re.search(r'dependencies\s*=\s*\[(.*?)\]', project_content, re.DOTALL)
    dep_list = []
    if dependencies:
        deps = re.findall(r'"([^"]+)"', dependencies.group(1))
        for dep in deps:
            if ">=" in dep or "==" in dep or "~=" in dep:
                pkg_name = re.split(r'[>=<~]', dep)[0]
                version_spec = dep[len(pkg_name):]
                dep_list.append((pkg_name, f'"{version_spec}"'))
            else:
                dep_list.append((dep, '"*"'))
    
    # Extract dev dependencies
    dev_deps = []
    dep_groups = re.search(r'\[dependency-groups\](.*?)(?=\n\[|\Z)', content, re.DOTALL)
    if dep_groups:
        dev_section = re.search(r'dev\s*=\s*\[(.*?)\]', dep_groups.group(1), re.DOTALL)
        if dev_section:
            dev_deps_raw = re.findall(r'"([^"]+)"', dev_section.group(1))
            for dep in dev_deps_raw:
                if ">=" in dep or "==" in dep or "~=" in dep:
                    pkg_name = re.split(r'[>=<~]', dep)[0]
                    version_spec = dep[len(pkg_name):]
                    dev_deps.append((pkg_name, f'"{version_spec}"'))
                else:
                    dev_deps.append((dep, '"*"'))
    
    # Extract URLs
    urls_section = re.search(r'\[project\.urls\](.*?)(?=\n\[|\Z)', content, re.DOTALL)
    urls = {}
    if urls_section:
        homepage = re.search(r'Homepage\s*=\s*"([^"]+)"', urls_section.group(1))
        repo = re.search(r'Repository\s*=\s*"([^"]+)"', urls_section.group(1))
        docs = re.search(r'Documentation\s*=\s*"([^"]+)"', urls_section.group(1))
        if homepage:
            urls['homepage'] = homepage.group(1)
        if repo:
            urls['repository'] = repo.group(1)
        if docs:
            urls['documentation'] = docs.group(1)
    
    # Extract scripts
    scripts_section = re.search(r'\[project\.scripts\](.*?)(?=\n\[|\Z)', content, re.DOTALL)
    scripts = []
    if scripts_section:
        script_matches = re.findall(r'(\w+(?:-\w+)*)\s*=\s*"([^"]+)"', scripts_section.group(1))
        scripts = script_matches
    
    # Detect package structure
    src_dir = Path("src")
    packages_config = ""
    if src_dir.exists():
        # Find first directory in src/
        subdirs = [d for d in src_dir.iterdir() if d.is_dir() and not d.name.startswith('.')]
        if subdirs:
            pkg_name = subdirs[0].name
            packages_config = f'packages = [{{include = "{pkg_name}", from = "src"}}]'
    else:
        # Look for package in root
        if name:
            pkg_name = name.group(1).replace('-', '_')
            pkg_path = Path(pkg_name)
            if pkg_path.exists() and pkg_path.is_dir():
                packages_config = f'packages = [{{include = "{pkg_name}"}}]'
    
    # Build new pyproject.toml
    new_content = "[tool.poetry]\n"
    
    if name:
        new_content += f'name = "{name.group(1)}"\n'
    if version:
        new_content += f'version = "{version.group(1)}"\n'
    if description:
        new_content += f'description = "{description.group(1)}"\n'
    if authors_list:
        new_content += f'authors = [{", ".join(authors_list)}]\n'
    if license_match:
        new_content += f'license = "{license_match.group(1)}"\n'
    if readme:
        new_content += f'readme = "{readme.group(1)}"\n'
    
    # Add URLs
    if 'homepage' in urls:
        new_content += f'homepage = "{urls["homepage"]}"\n'
    if 'repository' in urls:
        new_content += f'repository = "{urls["repository"]}"\n'
    if 'documentation' in urls:
        new_content += f'documentation = "{urls["documentation"]}"\n'
    
    if keywords:
        new_content += f'keywords = {keywords.group(1)}\n'
    if classifiers:
        new_content += f'classifiers = {classifiers.group(1)}\n'
    if packages_config:
        new_content += f'{packages_config}\n'
    
    # Dependencies section
    new_content += "\n[tool.poetry.dependencies]\n"
    if requires_python:
        python_version = requires_python.group(1).replace(">=", "^")
        new_content += f'python = "{python_version}"\n'
    else:
        new_content += 'python = "^3.10"\n'
    
    for dep_name, dep_version in dep_list:
        new_content += f'{dep_name} = {dep_version}\n'
    
    # Dev dependencies
    if dev_deps:
        new_content += "\n[tool.poetry.group.dev.dependencies]\n"
        for dep_name, dep_version in dev_deps:
            new_content += f'{dep_name} = {dep_version}\n'
    
    # Scripts
    if scripts:
        new_content += "\n[tool.poetry.scripts]\n"
        for script_name, script_target in scripts:
            new_content += f'{script_name} = "{script_target}"\n'
    
    # Build system
    new_content += "\n[build-system]\n"
    new_content += 'requires = ["poetry-core"]\n'
    new_content += 'build-backend = "poetry.core.masonry.api"\n'
    
    # Write the new file
    pyproject_path.write_text(new_content)
    print("Conversion complete!")

if __name__ == "__main__":
    try:
        convert_toml()
    except Exception as e:
        print(f"Error during conversion: {e}", file=sys.stderr)
        sys.exit(1)
EOF
    
    if [[ $? -eq 0 ]]; then
        print_success "pyproject.toml converted successfully"
    else
        print_error "Failed to convert pyproject.toml"
        print_info "Restoring backup..."
        mv pyproject.toml.uv-backup pyproject.toml
        exit 1
    fi
    
    # Step 7: Remove UV lock file
    if [[ -f "uv.lock" ]]; then
        print_info "Removing uv.lock..."
        rm uv.lock
        print_success "uv.lock removed"
    fi
    
    # Step 8: Clean up old virtual environment (optional)
    if [[ -d ".venv" ]]; then
        print_warning "Found .venv directory (UV virtual environment)"
        read -p "Remove it? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf .venv
            print_success ".venv removed"
        fi
    fi
    
    # Step 9: Initialize Poetry
    print_info "Installing dependencies with Poetry..."
    if poetry install; then
        print_success "Dependencies installed successfully"
    else
        print_error "Failed to install dependencies"
        print_warning "You may need to manually adjust pyproject.toml"
        exit 1
    fi
    
    # Step 10: Verify installation
    print_header "Verification"
    
    print_info "Poetry environment info:"
    poetry env info
    
    echo ""
    print_success "Conversion completed successfully!"
    echo ""
    print_info "Next steps:"
    echo "  1. Review the converted pyproject.toml"
    echo "  2. Test your project: poetry run <command>"
    echo "  3. If everything works, commit the changes:"
    echo "     git add pyproject.toml poetry.lock"
    echo "     git rm uv.lock"
    echo "     git commit -m 'Convert from uv to poetry'"
    echo ""
    print_info "Backup saved as: pyproject.toml.uv-backup"
    echo ""
}

# Script entry point
main() {
    if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
        cat << EOF
UV to Poetry Converter Script

Usage: $0 [project_directory]

Arguments:
  project_directory    Path to the project to convert (default: current directory)

Options:
  -h, --help          Show this help message

Examples:
  $0                          # Convert current directory
  $0 /path/to/project         # Convert specific directory
  $0 ~/projects/my-app        # Convert project in home directory

This script will:
  1. Check prerequisites (Poetry, Python)
  2. Backup pyproject.toml
  3. Convert pyproject.toml to Poetry format
  4. Remove uv.lock
  5. Install dependencies with Poetry
  6. Verify the installation

EOF
        exit 0
    fi
    
    convert_uv_to_poetry "${1:-.}"
}

# Run main function
main "$@"
