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


def _extract_setuptools_packages(pyproject_content: str) -> List[str]:
    """Best-effort extraction of setuptools `packages = [...]`.

    This is intentionally regex-based (no TOML dependency) and aims to preserve
    explicit packaging intent like:

        [tool.setuptools]
        packages = ["scripts"]

    Returns:
        List of package names, or empty list if not found.
    """

    setuptools_match = re.search(
        r'\[tool\.setuptools\](.*?)(?=\n\[|\Z)',
        pyproject_content,
        re.DOTALL,
    )
    if not setuptools_match:
        return []

    setuptools_section = setuptools_match.group(1)
    packages_match = re.search(r'packages\s*=\s*\[(.*?)\]', setuptools_section, re.DOTALL)
    if not packages_match:
        return []

    return re.findall(r'"([^"]+)"', packages_match.group(1))


def _poetry_packages_config(packages: List[str], *, from_dir: Optional[str] = None) -> str:
    """Render a Poetry `packages = [...]` config line."""

    entries: List[str] = []
    for pkg in packages:
        if from_dir:
            entries.append(f'{{include = "{pkg}", from = "{from_dir}"}}')
        else:
            entries.append(f'{{include = "{pkg}"}}')

    return f'packages = [{", ".join(entries)}]'


def detect_package_structure(
    project_dir: Path,
    project_name: Optional[str],
    pyproject_content: str,
) -> str:
    """Detect the package structure and return Poetry `packages = ...` configuration."""

    # 1) Respect explicit setuptools packaging when present.
    setuptools_packages = _extract_setuptools_packages(pyproject_content)
    if setuptools_packages:
        src_dir = project_dir / "src"
        if src_dir.exists() and src_dir.is_dir() and all(
            (src_dir / pkg).is_dir() for pkg in setuptools_packages
        ):
            return _poetry_packages_config(setuptools_packages, from_dir="src")

        # Root-layout fallback
        if all((project_dir / pkg).is_dir() for pkg in setuptools_packages):
            return _poetry_packages_config(setuptools_packages)

        # If the directories don't exist (edge case), still preserve intent.
        return _poetry_packages_config(setuptools_packages)

    # 2) Heuristic: src/ layout
    src_dir = project_dir / "src"
    if src_dir.exists() and src_dir.is_dir():
        subdirs = [d for d in src_dir.iterdir() if d.is_dir() and not d.name.startswith('.')]
        if subdirs:
            return _poetry_packages_config([subdirs[0].name], from_dir="src")

    # 3) Heuristic: root package matches project name
    if project_name:
        pkg_name = project_name.replace('-', '_')
        pkg_path = project_dir / pkg_name
        if pkg_path.exists() and pkg_path.is_dir():
            return _poetry_packages_config([pkg_name])

    return ""


def _extract_preserved_sections(pyproject_content: str) -> str:
    """Extract TOML sections to preserve when rewriting pyproject.toml.

    We intentionally drop UV/PEP 621 project metadata sections and replace them with
    Poetry equivalents, but keep tool configuration (ruff, mypy, pytest, etc.).

    This is best-effort and does not fully parse TOML; it groups content by section
    headers like `[tool.ruff]` or `[[tool.mypy.overrides]]`.
    """

    header_re = re.compile(r'^\s*\[\[?([^\]]+)\]\]?\s*(?:#.*)?$')

    def should_drop(section_name: str) -> bool:
        section_name = section_name.strip()
        if section_name == "project" or section_name.startswith("project."):
            return True
        if section_name == "dependency-groups" or section_name.startswith("dependency-groups."):
            return True
        if section_name == "build-system":
            return True
        if section_name.startswith("tool.setuptools"):
            return True
        if section_name.startswith("tool.poetry"):
            return True
        return False

    lines = pyproject_content.splitlines(keepends=True)
    blocks: List[str] = []
    current_block: List[str] = []
    current_section: Optional[str] = None

    for line in lines:
        m = header_re.match(line)
        if m:
            # Flush previous block
            if current_block and current_section and not should_drop(current_section):
                blocks.append("".join(current_block).rstrip() + "\n")
            current_block = [line]
            current_section = m.group(1)
        else:
            if current_section is not None:
                current_block.append(line)

    # Flush last block
    if current_block and current_section and not should_drop(current_section):
        blocks.append("".join(current_block).rstrip() + "\n")

    preserved = "\n".join(b.rstrip() for b in blocks).strip()
    return (preserved + "\n") if preserved else ""


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
        packages_config = detect_package_structure(project_dir, name, content)
        
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
            # Poetry supports PEP 440-style constraints (e.g. ">=3.10"), so keep as-is.
            lines.append(f'python = "{requires_python}"')
        else:
            lines.append('python = ">=3.10"')
        
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
        
        preserved_sections = _extract_preserved_sections(content)

        # Write the new file
        new_content = "\n".join(lines) + "\n"
        if preserved_sections:
            new_content = new_content.rstrip() + "\n\n" + preserved_sections

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
    
    # Step 3: Check if this is a UV project (best-effort)
    content = pyproject_path.read_text()

    def _looks_like_uv_project(*, project_dir: Path, pyproject_content: str) -> bool:
        if (project_dir / "uv.lock").exists():
            return True
        if "[tool.uv]" in pyproject_content:
            return True
        # Common in uv-managed projects; also used by newer standards, but a decent signal.
        if "[dependency-groups]" in pyproject_content:
            return True
        return False

    if not _looks_like_uv_project(project_dir=project_dir, pyproject_content=content):
        print_warning("This doesn't appear to be a UV project (no uv.lock/[tool.uv]/[dependency-groups] found)")
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
