#!/usr/bin/env python3
"""
Convert pip requirements.txt to Poetry pyproject.toml
"""
import re
import sys
from pathlib import Path


def parse_requirements(requirements_file):
    """Parse requirements.txt and categorize dependencies."""
    main_deps = []
    dev_deps = []
    current_section = "main"
    
    with open(requirements_file, 'r') as f:
        for line in f:
            line = line.strip()
            
            # Skip empty lines
            if not line:
                continue
            
            # Check for section comments
            if "testing" in line.lower() or "development" in line.lower() or "dev " in line.lower():
                current_section = "dev"
                continue
            elif line.startswith("#"):
                continue
            
            # Parse package specification
            # Handle: package, package==version, package>=version, package~=version, etc.
            match = re.match(r'^([a-zA-Z0-9_-]+)([=<>~!]+.*)?', line)
            if match:
                package = match.group(1)
                version = match.group(2) if match.group(2) else ""
                
                # Convert version specifiers to Poetry format
                if version:
                    version = version.replace("==", "")
                    version = version.replace(">=", "^")
                    version = version.replace("~=", "~")
                    version = f'"{version}"'
                else:
                    version = '"*"'
                
                if current_section == "dev":
                    dev_deps.append((package, version))
                else:
                    main_deps.append((package, version))
    
    return main_deps, dev_deps


def generate_pyproject_toml(main_deps, dev_deps, project_name="my-project"):
    """Generate pyproject.toml content."""
    toml_content = f'''[tool.poetry]
name = "{project_name}"
version = "0.1.0"
description = ""
authors = ["Your Name <you@example.com>"]
readme = "README.md"
package-mode = false

[tool.poetry.dependencies]
python = "^3.8"
'''
    
    for package, version in main_deps:
        toml_content += f'{package} = {version}\n'
    
    if dev_deps:
        toml_content += '\n[tool.poetry.group.dev.dependencies]\n'
        for package, version in dev_deps:
            toml_content += f'{package} = {version}\n'
    
    toml_content += '''
[build-system]
requires = ["poetry-core"]
build-backend = "poetry.core.masonry.api"
'''
    
    return toml_content


def main():
    if len(sys.argv) < 2:
        print("Usage: python pip_to_poetry.py <requirements.txt> [project-name]")
        sys.exit(1)
    
    requirements_file = sys.argv[1]
    project_name = sys.argv[2] if len(sys.argv) > 2 else Path.cwd().name
    
    if not Path(requirements_file).exists():
        print(f"Error: {requirements_file} not found")
        sys.exit(1)
    
    print(f"Converting {requirements_file} to pyproject.toml...")
    
    main_deps, dev_deps = parse_requirements(requirements_file)
    toml_content = generate_pyproject_toml(main_deps, dev_deps, project_name)
    
    output_file = "pyproject.toml"
    with open(output_file, 'w') as f:
        f.write(toml_content)
    
    print(f"✓ Created {output_file}")
    print(f"  - {len(main_deps)} main dependencies")
    print(f"  - {len(dev_deps)} dev dependencies")
    print("\nNext steps:")
    print("  1. Review and edit pyproject.toml as needed")
    print("  2. Run: poetry install")
    print("  3. Run: poetry lock")


if __name__ == "__main__":
    main()
