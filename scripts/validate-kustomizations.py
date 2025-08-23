#!/usr/bin/env python3
"""
Kustomization Schema Validator

Validates Kubernetes Kustomization files against the official JSON schema.
Can be run standalone or as part of CI/CD pipelines.

Usage:
    python3 scripts/validate-kustomizations.py [file_or_directory]
    
Examples:
    # Validate single file
    python3 scripts/validate-kustomizations.py kubernetes/apps/app/kustomization.yaml
    
    # Validate all kustomization files in directory
    python3 scripts/validate-kustomizations.py kubernetes/
    
    # Validate all kustomization files (default)
    python3 scripts/validate-kustomizations.py
"""

import json
import yaml
import sys
import os
import glob
import argparse
from pathlib import Path
from typing import Tuple, List, Optional

try:
    from jsonschema import validate, ValidationError
    import requests
except ImportError:
    print("❌ Missing dependencies. Install with:")
    print("   pip3 install jsonschema requests pyyaml")
    print("   # or")
    print("   sudo apt-get install python3-jsonschema python3-requests python3-yaml")
    sys.exit(1)


class KustomizationValidator:
    """Validates Kustomization files against the official JSON schema"""
    
    def __init__(self):
        self.schema = None
        self.schema_url = 'https://raw.githubusercontent.com/SchemaStore/schemastore/master/src/schemas/json/kustomization.json'
    
    def load_schema(self) -> bool:
        """Load the Kustomization schema from SchemaStore"""
        if self.schema is not None:
            return True
            
        try:
            print("📥 Downloading Kustomization schema...")
            response = requests.get(self.schema_url, timeout=30)
            response.raise_for_status()
            self.schema = response.json()
            print("✅ Schema loaded successfully")
            return True
        except Exception as e:
            print(f"❌ Failed to download schema: {e}")
            return False
    
    def validate_file(self, file_path: str) -> Tuple[bool, Optional[str]]:
        """Validate a single kustomization file"""
        try:
            # Load YAML file
            with open(file_path, 'r', encoding='utf-8') as f:
                data = yaml.safe_load(f)
            
            # Skip empty files
            if not data:
                return False, "File is empty or contains no YAML data"
            
            # Validate against schema
            validate(instance=data, schema=self.schema)
            return True, None
            
        except ValidationError as e:
            error_path = " → ".join(str(p) for p in e.path) if e.path else "root"
            return False, f"Schema validation failed at '{error_path}': {e.message}"
        except yaml.YAMLError as e:
            return False, f"YAML parsing error: {e}"
        except Exception as e:
            return False, f"Error processing file: {e}"
    
    def find_kustomization_files(self, path: str) -> List[str]:
        """Find all kustomization.yaml files in the given path"""
        if os.path.isfile(path):
            return [path] if path.endswith(('kustomization.yaml', 'kustomization.yml')) else []
        
        # Search for kustomization files
        patterns = [
            os.path.join(path, '**/kustomization.yaml'),
            os.path.join(path, '**/kustomization.yml')
        ]
        
        files = []
        for pattern in patterns:
            files.extend(glob.glob(pattern, recursive=True))
        
        return sorted(set(files))
    
    def validate_path(self, path: str) -> Tuple[int, int, List[str]]:
        """Validate all kustomization files in the given path"""
        files = self.find_kustomization_files(path)
        
        if not files:
            print(f"⚠️  No kustomization files found in: {path}")
            return 0, 0, []
        
        print(f"🔍 Found {len(files)} kustomization file(s) to validate")
        
        failed_files = []
        validated_count = 0
        
        for file_path in files:
            print(f"\nValidating: {file_path}")
            success, error = self.validate_file(file_path)
            
            if success:
                print(f"✅ Valid")
                validated_count += 1
            else:
                print(f"❌ {error}")
                failed_files.append(file_path)
        
        return validated_count, len(files), failed_files


def main():
    parser = argparse.ArgumentParser(
        description='Validate Kustomization files against official JSON schema',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s                                    # Validate all kustomization files
  %(prog)s kubernetes/                        # Validate files in kubernetes/ directory  
  %(prog)s apps/app/kustomization.yaml        # Validate single file
        """
    )
    parser.add_argument(
        'path', 
        nargs='?', 
        default='kubernetes',
        help='Path to kustomization file or directory (default: kubernetes)'
    )
    parser.add_argument(
        '--verbose', '-v',
        action='store_true',
        help='Enable verbose output'
    )
    
    args = parser.parse_args()
    
    # Check if path exists
    if not os.path.exists(args.path):
        print(f"❌ Path does not exist: {args.path}")
        sys.exit(1)
    
    # Initialize validator
    validator = KustomizationValidator()
    
    # Load schema
    if not validator.load_schema():
        sys.exit(1)
    
    print(f"\n🔍 Validating Kustomization files in: {args.path}")
    print("=" * 60)
    
    # Validate files
    validated_count, total_count, failed_files = validator.validate_path(args.path)
    
    # Print summary
    print("\n" + "=" * 60)
    print("📊 Validation Summary")
    print(f"   Total files: {total_count}")
    print(f"   Valid files: {validated_count}")
    print(f"   Failed files: {len(failed_files)}")
    
    if failed_files:
        print(f"\n💥 Failed validation for {len(failed_files)} file(s):")
        for file_path in failed_files:
            print(f"   - {file_path}")
        print("\n❌ Schema validation failed!")
        sys.exit(1)
    elif total_count > 0:
        print(f"\n🎉 All {validated_count} kustomization files pass schema validation!")
        sys.exit(0)
    else:
        print("\n⚠️  No kustomization files found to validate")
        sys.exit(0)


if __name__ == "__main__":
    main()
