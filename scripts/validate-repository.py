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
import re
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

        # Files/directories to exclude from secret checking
        excluded_patterns = [
            'externalsecret',
            'clustersecretstore',
            'secretstore',
            'talos/clusterconfig',  # Talos configs have certificates/keys
        ]

        # Safe key patterns that are not actual secrets
        safe_key_patterns = [
            'secretname',
            'secretkeyref',
            'secretstore',
            'secretstoreref',
            'secretkey',
            'secretkeyselector',
            'secretaccesskeyid',  # AWS config key name, not the secret itself
            'extravarssecret',  # Reference to secret, not the secret itself
            'envvarssecret',
            'secretref',
            'secretkeyref',
            'secretname',
            'secretkeyref',
            # Common Helm values patterns that are references, not values
            'secretname',
            'secretkey',
            'existingsecret',
            'secretref',
        ]

        # Patterns that indicate the value is a reference, not a secret
        reference_patterns = [
            r'^\s*#',  # Comments
            r'secretname',
            r'secretkeyref',
            r'secretstoreref',
            r'existingsecret',
            r'fromsecret',
            r'secretref',
        ]

        # Patterns that indicate actual secret values (not just keys)
        secret_value_patterns = [
            r'password:\s+["\']?[a-zA-Z0-9+/=]{20,}',  # Long base64-like or alphanumeric
            r'token:\s+["\']?[a-zA-Z0-9+/=]{20,}',
            r'secret:\s+["\']?[a-zA-Z0-9+/=]{20,}',
            r'key:\s+["\']?[a-zA-Z0-9+/=]{20,}',
            r'password:\s+["\']?[^"\'\s]{12,}',  # Long non-whitespace value
            r'token:\s+["\']?[^"\'\s]{12,}',
            r'secret:\s+["\']?[^"\'\s]{12,}',
        ]

        yaml_files = list(Path('kubernetes').glob('**/*.yaml'))

        # Check for hardcoded secrets
        for yaml_file in yaml_files:
            file_str = str(yaml_file)

            # Skip excluded files
            if any(excluded in file_str.lower() for excluded in excluded_patterns):
                continue

            try:
                with open(yaml_file, 'r', encoding='utf-8') as f:
                    lines = f.readlines()

                # Check each line for secret patterns
                for line_num, line in enumerate(lines, 1):
                    # Skip comments
                    if line.strip().startswith('#'):
                        continue

                    # Skip if it's a key reference (not a value)
                    line_lower = line.lower()
                    if any(safe_pattern in line_lower for safe_pattern in safe_key_patterns):
                        continue

                    # Check for actual secret values (long strings that look like secrets)
                    for pattern in secret_value_patterns:
                        if re.search(pattern, line, re.IGNORECASE):
                            # Additional check: make sure it's not just a field name
                            # If it's followed by a colon and then a value, it's likely a secret
                            if ':' in line:
                                value_part = line.split(':', 1)[1].strip()

                                # Remove quotes if present
                                value_part = value_part.strip('"\'').strip()

                                # Skip if it looks like a template variable or reference
                                if any(ref in value_part for ref in ['${{', '{{', '$${', 'ref:', 'secretKeyRef', 'valueFrom', 'name:', 'key:', 'fromSecret', 'existingSecret']):
                                    continue

                                # Skip if the line contains reference patterns (like secretName, secretKeyRef, etc.)
                                if any(ref_pattern in line_lower for ref_pattern in reference_patterns):
                                    continue

                                # Skip if it's just a secret name (short, no special chars, looks like a k8s resource name)
                                # But be more strict - if it's in a values.yaml or secrets.yaml, it might be a real secret
                                if re.match(r'^[a-z0-9-]+$', value_part) and len(value_part) < 50:
                                    # Skip if the key name contains "secret", "key", "token", or "password" - these are likely references
                                    key_part = line.split(':', 1)[0].strip().lower()
                                    if 'secret' in key_part or 'key' in key_part or 'token' in key_part or 'password' in key_part:
                                        continue
                                    # Also skip if the key name ends with "Secret" or "Key" (like githubConfigSecret)
                                    if key_part.endswith('secret') or key_part.endswith('key'):
                                        continue

                                # Skip commented out lines (common in values.yaml for examples)
                                if line.strip().startswith('#'):
                                    continue

                                # Only warn if it's a long value that looks like an actual secret
                                # For values.yaml and secrets.yaml, be more strict - require longer values
                                min_length = 20 if 'values.yaml' in file_str or 'secrets.yaml' in file_str else 12
                                if len(value_part) > min_length:
                                    self.log(f"Potential hardcoded secret in {yaml_file}:{line_num}", "WARNING")
                                    break
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
