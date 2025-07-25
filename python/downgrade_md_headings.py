#!/usr/bin/env python3
"""
Script to process markdown headings by increasing their level:
# becomes ##
## becomes ###
### becomes ####

Simple character replacement approach.
"""

import sys

def process_headings(file_path):
    """
    Process markdown headings by adding one more # to each heading.
    
    Args:
        file_path (str): Path to the markdown file to process
    """
    
    # Read the file
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()
    except FileNotFoundError:
        print(f"Error: File '{file_path}' not found.")
        return False
    except Exception as e:
        print(f"Error reading file: {e}")
        return False
    
    modifications_count = 0
    
    # Process each line
    for i, line in enumerate(lines):
        # Check if line starts with #
        if line.startswith('#'):
            # Count the number of # characters at the start
            hash_count = 0
            for char in line:
                if char == '#':
                    hash_count += 1
                else:
                    break
            
            # Only process if followed by a space (proper markdown heading)
            if hash_count > 0 and len(line) > hash_count and line[hash_count] == ' ':
                # Replace with one more #
                new_line = '#' * (hash_count + 1) + line[hash_count:]
                lines[i] = new_line
                modifications_count += 1
                print(f"Line {i + 1}: {line.strip()} -> {new_line.strip()}")
    
    if modifications_count == 0:
        print("No headings found to process.")
        return True
    
    # Write the modified content back to the file
    try:
        with open(file_path, 'w', encoding='utf-8') as f:
            f.writelines(lines)
        print(f"\nSuccessfully processed {modifications_count} headings in '{file_path}'")
        return True
    except Exception as e:
        print(f"Error writing file: {e}")
        return False

def main():
    if len(sys.argv) != 2:
        print("Usage: python process_headings.py <file_path>")
        print("Example: python process_headings.py chat-export.md")
        sys.exit(1)
    
    file_path = sys.argv[1]
    success = process_headings(file_path)
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main() 