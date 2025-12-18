#!/usr/bin/env python3

"""
UV to Poetry Converter Script (Python)

This script automates the conversion of Python projects from uv to Poetry
package management.

Usage: python3 convert-uv-to-poetry.py [project_directory]

Author: Auto-generated
License: MIT
"""

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple


class Colors:
    """ANSI color codes for terminal output"""
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    BOLD = '\033[1m'
    NC = '\033[0m'  # No Color


def print_success(message: str) -> None:
    """Print a success message"""
    print(f"{Colors.GREEN}✓{Colors.NC} {message}")


def print_error(message: str) -> None:
    """Print an error message"""
    print(f"{Colors.RED}✗{Colors.NC} {message}", file=sys.stderr)


def print_warning(message: str) -> None:
    """Print a warning message"""
    print(f"{Colors.YELLOW}⚠{Colors.NC} {message}")


def print_info(message: str) -> None:
    """Print an info message"""
    print(f"{Colors.BLUE}ℹ{Colors.NC} {message}")


def print_header(message: str) -> None:
    """Print a section header"""
    print()
    print("━" * 60)
    print(f"  {message}")
    print("━" * 60)
    print()


def command_exists(command: str) -> bool:
    """Check if a command exists in PATH"""
    return shutil.which(command) is not None


def run_command(cmd: List[str], cwd: Optional[Path] = None) -> Tuple[bool, str, str]:
    """
    Run a command and return success status, stdout, and stderr
    
    Args:
        cmd: Command and arguments as list
        cwd: Working directory for command
        
    Returns:
        Tuple of (success: bool, stdout: str, stderr: str)
    """
    try:
        result = subprocess.run(
            cmd,
            cwd=cwd,
            capture_output=True,
            text=True,
            check=False
        )
        return result.returncode == 0, result.stdout, result.stderr
    except Exception as e:
        return False, "", str(e)


def extract_field(content: str, field: str, multiline: bool = False) -> Optional[str]:
    """Extract a field value from TOML content"""
    if multiline:
        pattern = rf'{field}\s*=\s*(\[.*?\])'
        match = re.search(pattern, content, re.DOTALL)
    else:
        pattern = rf'{field}\s*=\s*"([^"]+)"'
        match = re.search(pattern, content)
    return match.group(1) if match else None


def extract_authors(content: str) -> List[str]:
    """Extract and convert authors from UV format to Poetry format"""
    authors_list = []
    authors_match = re.search(r'authors\s*=\s*\[(.*?)\]', content, re.DOTALL)
    
    if authors_match:
        author_dicts = re.findall(
            r'\{\s*name\s*=\s*"([^"]+)"(?:,\s*email\s*=\s*"([^"]+)")?\s*\}',
            authors_match.group(1)
        )
        for name, email in author_dicts:
            if email:
                authors_list.append(f'"{name} <{email}>"')
            else:
                authors_list.append(f'"{name}"')
    
    return authors_list


def extract_dependencies(content: str, section_name: str) -> List[Tuple[str, str]]:
    """Extract dependencies from a TOML section"""
    dep_list = []
    pattern = rf'{section_name}\s*=\s*\[(.*?)\]'
    match = re.search(pattern, content, re.DOTALL)
    
    if match:
        deps = re.findall(r'"([^"]+)"', match.group(1))
        for dep in deps:
            if any(op in dep for op in ['>=', '==', '~=', '<', '>']):
                pkg_name = re.split(r'[>=<~]', dep)[0]
                version_spec = dep[len(pkg_name):]
                dep_list.append((pkg_name, f'"{version_spec}"'))
            else:
                dep_list.append((dep, '"*"'))
    
    return dep_list


def extract_urls(content: str) -> Dict[str, str]:
    """Extract URLs from [project.urls] section"""
    urls = {}
    urls_match = re.search(r'\[project\.urls\](.*?)(?=\n\[|\Z)', content, re.DOTALL)
    
    if urls_match:
        urls_content = urls_match.group(1)
        for key, url_key in [('Homepage', 'homepage'), ('Repository', 'repository'),
                              ('Documentation', 'documentation')]:
            match = re.search(rf'{key}\s*=\s*"([^"]+)"', urls_content)
            if match:
                urls[url_key] = match.group(1)
    
    return urls


def extract_scripts(content: str) -> List[Tuple[str, str]]:
    """Extract scripts from [project.scripts] section"""
    scripts = []
    scripts_match = re.search(r'\[project\.scripts\](.*?)(?=\n\[|\Z)', content, re.DOTALL)
    
    if scripts_match:
        scripts = re.findall(r'(\w+(?:-\w+)*)\s*=\s*"([^"]+)"', scripts_match.group(1))
    
    return scripts


def detect_package_structure(project_dir: Path, project_name: Optional[str]) -> str:
    """Detect the package structure and return packages configuration"""
    src_dir = project_dir / "src"
    
    if src_dir.exists() and src_dir.is_dir():
        # Look for first directory in src/
        subdirs = [d for d in src_dir.iterdir() 
                   if d.is_dir() and not d.name.startswith('.')]
        if subdirs:
            pkg_name = subdirs[0].name
            return f'packages = [{{include = "{pkg_name}", from = "src"}}]'
    
    # Look for package in root directory
    if project_name:
        pkg_name = project_name.replace('-', '_')
        pkg_path = project_dir / pkg_name
        if pkg_path.exists() and pkg_path.is_dir():
            return f'packages = [{{include = "{pkg_name}"}}]'
    
    return ""


def convert_pyproject_toml(project_dir: Path) -> bool:
    """
    Convert pyproject.toml from UV format to Poetry format
    
    Args:
        project_dir: Path to project directory
        
    Returns:
        True if conversion was successful, False otherwise
    """
    pyproject_path = project_dir / "pyproject.toml"
    
    try:
        content = pyproject_path.read_text()
        
        # Extract [project] section
        project_match = re.search(r'\[project\](.*?)(?=\n\[|\Z)', content, re.DOTALL)
        if not project_match:
            print_error("No [project] section found in pyproject.toml")
            return False
        
        project_content = project_match.group(1)
        
        # Extract all fields
        name = extract_field(project_content, 'name')
        version = extract_field(project_content, 'version')
        description = extract_field(project_content, 'description')
        readme = extract_field(project_content, 'readme')
        license_val = extract_field(project_content, 'license')
        requires_python = extract_field(project_content, 'requires-python')
        keywords = extract_field(project_content, 'keywords', multiline=True)
        classifiers = extract_field(project_content, 'classifiers', multiline=True)
        
        authors = extract_authors(project_content)
        dependencies = extract_dependencies(project_content, 'dependencies')
        urls = extract_urls(content)
        scripts = extract_scripts(content)
        
        # Extract dev dependencies
        dev_deps = []
        dep_groups_match = re.search(r'\[dependency-groups\](.*?)(?=\n\[|\Z)', 
                                      content, re.DOTALL)
        if dep_groups_match:
            dev_deps = extract_dependencies(dep_groups_match.group(1), 'dev')
        
        # Detect package structure
        packages_config = detect_package_structure(project_dir, name)
        
        # Build new pyproject.toml content
        lines = ["[tool.poetry]"]
        
        if name:
            lines.append(f'name = "{name}"')
        if version:
            lines.append(f'version = "{version}"')
        if description:
            lines.append(f'description = "{description}"')
        if authors:
            lines.append(f'authors = [{", ".join(authors)}]')
        if license_val:
            lines.append(f'license = "{license_val}"')
        if readme:
            lines.append(f'readme = "{readme}"')
        
        # Add URLs
        for url_key in ['homepage', 'repository', 'documentation']:
            if url_key in urls:
                lines.append(f'{url_key} = "{urls[url_key]}"')
        
        if keywords:
            lines.append(f'keywords = {keywords}')
        if classifiers:
            lines.append(f'classifiers = {classifiers}')
        if packages_config:
            lines.append(packages_config)
        
        # Dependencies section
        lines.append("")
        lines.append("[tool.poetry.dependencies]")
        
        if requires_python:
            python_version = requires_python.replace(">=", "^")
            lines.append(f'python = "{python_version}"')
        else:
            lines.append('python = "^3.10"')
        
        for dep_name, dep_version in dependencies:
            lines.append(f'{dep_name} = {dep_version}')
        
        # Dev dependencies
        if dev_deps:
            lines.append("")
            lines.append("[tool.poetry.group.dev.dependencies]")
            for dep_name, dep_version in dev_deps:
                lines.append(f'{dep_name} = {dep_version}')
        
        # Scripts
        if scripts:
            lines.append("")
            lines.append("[tool.poetry.scripts]")
            for script_name, script_target in scripts:
                lines.append(f'{script_name} = "{script_target}"')
        
        # Build system
        lines.append("")
        lines.append("[build-system]")
        lines.append('requires = ["poetry-core"]')
        lines.append('build-backend = "poetry.core.masonry.api"')
        
        # Write the new file
        new_content = "\n".join(lines) + "\n"
        pyproject_path.write_text(new_content)
        
        return True
        
    except Exception as e:
        print_error(f"Error during conversion: {e}")
        return False


def convert_project(project_dir: Path) -> bool:
    """
    Main function to convert a project from UV to Poetry
    
    Args:
        project_dir: Path to project directory
        
    Returns:
        True if conversion was successful, False otherwise
    """
    print_header("UV to Poetry Converter")
    
    # Step 1: Check prerequisites
    print_info("Checking prerequisites...")
    
    if not command_exists("poetry"):
        print_error("Poetry is not installed")
        print()
        print("Install Poetry using one of these methods:")
        print("  • Official installer: curl -sSL https://install.python-poetry.org | python3 -")
        print("  • Homebrew (macOS): brew install poetry")
        print("  • pipx: pipx install poetry")
        return False
    
    success, stdout, _ = run_command(["poetry", "--version"])
    if success:
        print_success(f"Poetry is installed ({stdout.strip()})")
    
    if not command_exists("python3"):
        print_error("Python 3 is not installed")
        return False
    
    success, stdout, _ = run_command(["python3", "--version"])
    if success:
        print_success(f"Python 3 is installed ({stdout.strip()})")
    
    # Step 2: Validate project directory
    print_info(f"Validating project directory: {project_dir}")
    
    if not project_dir.exists():
        print_error(f"Directory does not exist: {project_dir}")
        return False
    
    if not project_dir.is_dir():
        print_error(f"Path is not a directory: {project_dir}")
        return False
    
    pyproject_path = project_dir / "pyproject.toml"
    if not pyproject_path.exists():
        print_error(f"pyproject.toml not found in {project_dir}")
        return False
    
    print_success(f"Found pyproject.toml")
    
    # Step 3: Check if this is a UV project
    content = pyproject_path.read_text()
    if "[build-system]" not in content or "uv" not in content:
        print_warning("This doesn't appear to be a UV project")
        response = input("Continue anyway? (y/N): ")
        if response.lower() != 'y':
            print_info("Conversion cancelled")
            return False
    
    # Step 4: Backup original pyproject.toml
    print_info("Creating backup of pyproject.toml...")
    backup_path = project_dir / "pyproject.toml.uv-backup"
    shutil.copy2(pyproject_path, backup_path)
    print_success(f"Backup created: {backup_path.name}")
    
    # Step 5: Convert pyproject.toml
    print_info("Converting pyproject.toml to Poetry format...")
    
    if not convert_pyproject_toml(project_dir):
        print_error("Failed to convert pyproject.toml")
        print_info("Restoring backup...")
        shutil.copy2(backup_path, pyproject_path)
        return False
    
    print_success("pyproject.toml converted successfully")
    
    # Step 6: Remove UV lock file
    uv_lock = project_dir / "uv.lock"
    if uv_lock.exists():
        print_info("Removing uv.lock...")
        uv_lock.unlink()
        print_success("uv.lock removed")
    
    # Step 7: Clean up old virtual environment (optional)
    venv_dir = project_dir / ".venv"
    if venv_dir.exists():
        print_warning("Found .venv directory (UV virtual environment)")
        response = input("Remove it? (y/N): ")
        if response.lower() == 'y':
            shutil.rmtree(venv_dir)
            print_success(".venv removed")
    
    # Step 8: Install dependencies with Poetry
    print_info("Installing dependencies with Poetry...")
    success, stdout, stderr = run_command(["poetry", "install"], cwd=project_dir)
    
    if not success:
        print_error("Failed to install dependencies")
        print_warning("You may need to manually adjust pyproject.toml")
        if stderr:
            print()
            print("Error output:")
            print(stderr)
        return False
    
    print_success("Dependencies installed successfully")
    
    # Step 9: Verify installation
    print_header("Verification")
    
    print_info("Poetry environment info:")
    success, stdout, _ = run_command(["poetry", "env", "info"], cwd=project_dir)
    if success:
        print(stdout)
    
    print()
    print_success("Conversion completed successfully!")
    print()
    print_info("Next steps:")
    print("  1. Review the converted pyproject.toml")
    print("  2. Test your project: poetry run <command>")
    print("  3. If everything works, commit the changes:")
    print("     git add pyproject.toml poetry.lock")
    print("     git rm uv.lock")
    print("     git commit -m 'Convert from uv to poetry'")
    print()
    print_info(f"Backup saved as: {backup_path.name}")
    print()
    
    return True


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description="Convert Python projects from uv to Poetry package management",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s                          # Convert current directory
  %(prog)s /path/to/project         # Convert specific directory
  %(prog)s ~/projects/my-app        # Convert project in home directory

This script will:
  1. Check prerequisites (Poetry, Python)
  2. Backup pyproject.toml
  3. Convert pyproject.toml to Poetry format
  4. Remove uv.lock
  5. Install dependencies with Poetry
  6. Verify the installation
        """
    )
    
    parser.add_argument(
        "project_dir",
        nargs="?",
        default=".",
        help="Path to the project to convert (default: current directory)"
    )
    
    args = parser.parse_args()
    
    project_dir = Path(args.project_dir).resolve()
    
    try:
        success = convert_project(project_dir)
        sys.exit(0 if success else 1)
    except KeyboardInterrupt:
        print()
        print_warning("Conversion interrupted by user")
        sys.exit(1)
    except Exception as e:
        print_error(f"Unexpected error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
