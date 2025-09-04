#!/usr/bin/env python3
"""
Comprehensive Repository Validator

Runs all validation checks for the Kubernetes infrastructure repository.
This script combines multiple validation tools to ensure repository quality,
security, and consistency.

Usage:
    python3 scripts/validate-repository.py [options]
    
Examples:
    # Run all validations
    python3 scripts/validate-repository.py
    
    # Run specific validation types
    python3 scripts/validate-repository.py --kustomizations --schemas
    
    # Skip certain validations
    python3 scripts/validate-repository.py --skip security
"""

import os
import sys
import argparse
import subprocess
from pathlib import Path
from typing import List, Dict, Tuple


class RepositoryValidator:
    """Comprehensive repository validation"""
    
    def __init__(self, verbose: bool = False):
        self.verbose = verbose
        self.errors = []
        self.warnings = []
        
    def log(self, message: str, level: str = "INFO"):
        """Log messages with appropriate formatting"""
        if level == "ERROR":
            print(f"❌ {message}")
            self.errors.append(message)
        elif level == "WARNING":
            print(f"⚠️  {message}")
            self.warnings.append(message)
        elif level == "SUCCESS":
            print(f"✅ {message}")
        else:
            if self.verbose:
                print(f"ℹ️  {message}")
    
    def run_command(self, cmd: List[str], description: str) -> Tuple[bool, str]:
        """Run a command and return success status and output"""
        try:
            self.log(f"Running: {description}", "INFO")
            result = subprocess.run(
                cmd, 
                capture_output=True, 
                text=True, 
                check=False
            )
            
            if result.returncode == 0:
                self.log(f"{description} - PASSED", "SUCCESS")
                return True, result.stdout
            else:
                self.log(f"{description} - FAILED", "ERROR")
                if result.stderr:
                    self.log(f"Error: {result.stderr.strip()}", "ERROR")
                return False, result.stderr
                
        except FileNotFoundError:
            self.log(f"{description} - SKIPPED (command not found)", "WARNING")
            return True, "Command not found"
        except Exception as e:
            self.log(f"{description} - ERROR: {e}", "ERROR")
            return False, str(e)
    
    def validate_yaml_syntax(self) -> bool:
        """Validate YAML syntax for all files"""
        self.log("🔍 Validating YAML syntax...")
        
        yaml_files = []
        for pattern in ['kubernetes/**/*.yaml', 'kubernetes/**/*.yml', '.github/**/*.yaml', '.github/**/*.yml']:
            yaml_files.extend(Path('.').glob(pattern))
        
        failed_files = []
        for yaml_file in yaml_files:
            try:
                import yaml
                with open(yaml_file, 'r', encoding='utf-8') as f:
                    yaml.safe_load_all(f.read())
            except yaml.YAMLError as e:
                failed_files.append(f"{yaml_file}: {e}")
            except Exception as e:
                failed_files.append(f"{yaml_file}: {e}")
        
        if failed_files:
            for error in failed_files:
                self.log(f"YAML syntax error: {error}", "ERROR")
            return False
        
        self.log(f"YAML syntax validation passed for {len(yaml_files)} files", "SUCCESS")
        return True
    
    def validate_kustomizations(self) -> bool:
        """Validate Kustomization files against schema"""
        if not os.path.exists('scripts/validate-kustomizations.py'):
            self.log("Kustomization validator not found", "WARNING")
            return True
            
        return self.run_command([
            'python3', 'scripts/validate-kustomizations.py'
        ], "Kustomization schema validation")[0]
    
    def validate_schema_alignment(self) -> bool:
        """Validate schema/apiVersion alignment"""
        if not os.path.exists('scripts/validate-schema-alignment.py'):
            self.log("Schema alignment validator not found", "WARNING")
            return True
            
        return self.run_command([
            'python3', 'scripts/validate-schema-alignment.py'
        ], "Schema alignment validation")[0]
    
    def validate_security(self) -> bool:
        """Run security validations"""
        self.log("🔒 Running security validations...")
        
        security_passed = True
        
        # Check for hardcoded secrets (basic check)
        secret_patterns = ['password:', 'token:', 'key:', 'secret:']
        yaml_files = list(Path('kubernetes').glob('**/*.yaml'))
        
        for yaml_file in yaml_files:
            try:
                with open(yaml_file, 'r', encoding='utf-8') as f:
                    content = f.read().lower()
                    for pattern in secret_patterns:
                        if pattern in content and 'externalsecret' not in str(yaml_file).lower():
                            # This is a basic check - could have false positives
                            self.log(f"Potential hardcoded secret in {yaml_file}", "WARNING")
            except Exception:
                continue
        
        # Check for privileged containers
        privileged_files = []
        for yaml_file in yaml_files:
            try:
                with open(yaml_file, 'r', encoding='utf-8') as f:
                    content = f.read()
                    if 'privileged: true' in content:
                        privileged_files.append(str(yaml_file))
            except Exception:
                continue
        
        if privileged_files:
            for file in privileged_files:
                self.log(f"Privileged container found in {file}", "WARNING")
        
        return security_passed
    
    def validate_documentation(self) -> bool:
        """Validate documentation completeness"""
        self.log("📚 Validating documentation...")
        
        required_docs = ['README.md', 'CONTRIBUTING.md', 'SECURITY.md']
        missing_docs = []
        
        for doc in required_docs:
            if not os.path.exists(doc):
                missing_docs.append(doc)
        
        if missing_docs:
            for doc in missing_docs:
                self.log(f"Missing documentation: {doc}", "WARNING")
        
        # Check for TODO comments
        todo_files = []
        for yaml_file in Path('kubernetes').glob('**/*.yaml'):
            try:
                with open(yaml_file, 'r', encoding='utf-8') as f:
                    content = f.read()
                    if 'TODO' in content or 'FIXME' in content:
                        todo_files.append(str(yaml_file))
            except Exception:
                continue
        
        if todo_files:
            self.log(f"Found TODO/FIXME comments in {len(todo_files)} files", "WARNING")
            if self.verbose:
                for file in todo_files:
                    self.log(f"  - {file}", "INFO")
        
        return True
    
    def validate_structure(self) -> bool:
        """Validate repository structure"""
        self.log("🏗️  Validating repository structure...")
        
        required_dirs = [
            'kubernetes/apps',
            'kubernetes/clusters', 
            'kubernetes/components',
            'scripts',
            '.github/workflows'
        ]
        
        missing_dirs = []
        for dir_path in required_dirs:
            if not os.path.exists(dir_path):
                missing_dirs.append(dir_path)
        
        if missing_dirs:
            for dir_path in missing_dirs:
                self.log(f"Missing directory: {dir_path}", "ERROR")
            return False
        
        self.log("Repository structure validation passed", "SUCCESS")
        return True
    
    def run_all_validations(self, skip: List[str] = None) -> bool:
        """Run all validation checks"""
        if skip is None:
            skip = []
        
        print("🚀 Starting comprehensive repository validation...")
        print("=" * 60)
        
        validations = [
            ('structure', self.validate_structure),
            ('yaml', self.validate_yaml_syntax),
            ('kustomizations', self.validate_kustomizations),
            ('schemas', self.validate_schema_alignment),
            ('security', self.validate_security),
            ('documentation', self.validate_documentation),
        ]
        
        results = {}
        for name, validation_func in validations:
            if name in skip:
                self.log(f"Skipping {name} validation", "INFO")
                continue
                
            try:
                results[name] = validation_func()
            except Exception as e:
                self.log(f"Validation {name} failed with exception: {e}", "ERROR")
                results[name] = False
        
        # Print summary
        print("\n" + "=" * 60)
        print("📊 Validation Summary")
        print("=" * 60)
        
        passed = sum(1 for result in results.values() if result)
        total = len(results)
        
        for name, result in results.items():
            status = "✅ PASSED" if result else "❌ FAILED"
            print(f"  {name.capitalize():<15} {status}")
        
        print(f"\nResults: {passed}/{total} validations passed")
        
        if self.errors:
            print(f"\n❌ Errors ({len(self.errors)}):")
            for error in self.errors:
                print(f"  - {error}")
        
        if self.warnings:
            print(f"\n⚠️  Warnings ({len(self.warnings)}):")
            for warning in self.warnings:
                print(f"  - {warning}")
        
        success = all(results.values()) and len(self.errors) == 0
        
        if success:
            print("\n🎉 All validations passed! Repository is in good shape.")
        else:
            print("\n💥 Some validations failed. Please address the issues above.")
        
        return success


def main():
    parser = argparse.ArgumentParser(
        description='Comprehensive repository validation',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s                           # Run all validations
  %(prog)s --verbose                 # Run with detailed output
  %(prog)s --skip security           # Skip security validation
  %(prog)s --kustomizations --schemas # Run only specific validations
        """
    )
    
    parser.add_argument('--verbose', '-v', action='store_true', help='Enable verbose output')
    parser.add_argument('--skip', nargs='+', help='Skip specific validations', 
                       choices=['structure', 'yaml', 'kustomizations', 'schemas', 'security', 'documentation'])
    
    # Individual validation flags
    parser.add_argument('--structure', action='store_true', help='Run only structure validation')
    parser.add_argument('--yaml', action='store_true', help='Run only YAML syntax validation')
    parser.add_argument('--kustomizations', action='store_true', help='Run only Kustomization validation')
    parser.add_argument('--schemas', action='store_true', help='Run only schema alignment validation')
    parser.add_argument('--security', action='store_true', help='Run only security validation')
    parser.add_argument('--documentation', action='store_true', help='Run only documentation validation')
    
    args = parser.parse_args()
    
    # Check if specific validations were requested
    specific_validations = [
        name for name in ['structure', 'yaml', 'kustomizations', 'schemas', 'security', 'documentation']
        if getattr(args, name)
    ]
    
    validator = RepositoryValidator(verbose=args.verbose)
    
    if specific_validations:
        # Run only specific validations
        success = True
        for validation in specific_validations:
            validation_func = getattr(validator, f'validate_{validation}')
            if not validation_func():
                success = False
    else:
        # Run all validations
        success = validator.run_all_validations(skip=args.skip or [])
    
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
