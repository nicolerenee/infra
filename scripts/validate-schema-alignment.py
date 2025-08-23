#!/usr/bin/env python3
"""
Schema/ApiVersion Alignment Validator

Validates that yaml-language-server schema URLs match the actual apiVersion
in Kubernetes YAML files. This prevents IDE validation issues and ensures
schema annotations are correct.

Usage:
    python3 scripts/validate-schema-alignment.py [directory]

Examples:
    # Check all files
    python3 scripts/validate-schema-alignment.py

    # Check specific directory
    python3 scripts/validate-schema-alignment.py kubernetes/apps/
"""

import os
import re
import yaml
import glob
import sys
import argparse
from pathlib import Path
from typing import List, Dict, Optional, Tuple


class SchemaAlignmentValidator:
    """Validates schema URL and apiVersion alignment"""

    def __init__(self):
        # Known schema mappings for common mismatches
        self.known_mappings = {
            # Kustomization files - schemastore.org schema supports both v1alpha1 and v1beta1
            'kustomize.config.k8s.io/v1alpha1': 'https://www.schemastore.org/kustomization.json',
            'kustomize.config.k8s.io/v1beta1': 'https://www.schemastore.org/kustomization.json',

            # Flux resources
            'source.toolkit.fluxcd.io/v1': 'ocirepository_v1.json',
            'source.toolkit.fluxcd.io/v1beta2': 'ocirepository_v1beta2.json',
            'helm.toolkit.fluxcd.io/v2': 'helmrelease_v2.json',

            # External Secrets
            'external-secrets.io/v1': 'clustersecretstore_v1.json',
            'external-secrets.io/v1beta1': 'clustersecretstore_v1beta1.json',
        }

        # Schema URLs that are valid for multiple API versions
        self.multi_version_schemas = {
            'https://www.schemastore.org/kustomization.json': ['1alpha1', '1beta1'],
            'https://json.schemastore.org/kustomization': ['1alpha1', '1beta1'],
        }

    def extract_schema_version(self, schema_url: str) -> Optional[str]:
        """Extract version from schema URL"""
        # Match patterns like ocirepository_v1.json, helmrelease_v2.json, etc.
        match = re.search(r'/([^/]+)_v(\d+(?:beta\d+|alpha\d+)?).json', schema_url)
        if match:
            return match.group(2)  # Return version part

        # Special case for schemastore.org kustomization
        if 'schemastore.org/kustomization' in schema_url:
            return '1beta1'  # Kustomization schema is for v1beta1 (return without 'v' prefix)

        return None

    def extract_api_version(self, api_version: str) -> Optional[str]:
        """Extract version from apiVersion"""
        # Match patterns like source.toolkit.fluxcd.io/v1, helm.toolkit.fluxcd.io/v2, etc.
        match = re.search(r'/v(\d+(?:beta\d+|alpha\d+)?)$', api_version)
        if match:
            return match.group(1)  # Return version part
        return None

    def get_expected_schema(self, api_version: str, kind: str) -> Optional[str]:
        """Get expected schema URL for given apiVersion and kind"""
        if api_version in self.known_mappings:
            return self.known_mappings[api_version]

        # Try to construct schema URL for common patterns
        if 'toolkit.fluxcd.io' in api_version:
            version = self.extract_api_version(api_version)
            if version and kind:
                kind_lower = kind.lower()
                return f"https://k8s-schemas.freckle.systems/{api_version.split('/')[0]}/{kind_lower}_v{version}.json"

        return None

    def check_file_for_mismatches(self, file_path: str) -> List[Dict]:
        """Check a single file for schema/apiVersion mismatches"""
        mismatches = []

        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()

            # Split by document separator to handle multi-document YAML
            documents = content.split('\n---\n')

            for i, doc in enumerate(documents):
                if not doc.strip():
                    continue

                schema_url = None
                api_version = None
                kind = None

                # Extract schema URL from yaml-language-server comment
                schema_match = re.search(r'yaml-language-server:\s*\$schema=([^\s]+)', doc)
                if schema_match:
                    schema_url = schema_match.group(1)

                # Extract apiVersion and kind from YAML
                try:
                    yaml_data = yaml.safe_load(doc)
                    if yaml_data and isinstance(yaml_data, dict):
                        api_version = yaml_data.get('apiVersion')
                        kind = yaml_data.get('kind')
                except:
                    continue

                # Check for mismatch
                if schema_url and api_version:
                    schema_version = self.extract_schema_version(schema_url)
                    api_version_part = self.extract_api_version(api_version)

                    # Check if this schema supports multiple API versions
                    is_valid = False
                    if schema_url in self.multi_version_schemas:
                        if api_version_part in self.multi_version_schemas[schema_url]:
                            is_valid = True

                    # Check if this is a known valid mapping
                    if api_version in self.known_mappings:
                        if schema_url == self.known_mappings[api_version]:
                            is_valid = True

                    if schema_version and api_version_part and not is_valid and schema_version != api_version_part:
                        expected_schema = self.get_expected_schema(api_version, kind)
                        mismatches.append({
                            'document': i,
                            'schema_url': schema_url,
                            'schema_version': schema_version,
                            'api_version': api_version,
                            'api_version_part': api_version_part,
                            'kind': kind,
                            'expected_schema': expected_schema
                        })

        except Exception as e:
            print(f"Error processing {file_path}: {e}")

        return mismatches

    def find_yaml_files_with_schemas(self, path: str) -> List[str]:
        """Find all YAML files with schema annotations"""
        if os.path.isfile(path):
            return [path] if path.endswith(('.yaml', '.yml')) else []

        # Find all YAML files
        patterns = [
            os.path.join(path, '**/*.yaml'),
            os.path.join(path, '**/*.yml')
        ]

        yaml_files = []
        for pattern in patterns:
            yaml_files.extend(glob.glob(pattern, recursive=True))

        # Filter to only files with schema annotations
        schema_files = []
        for file_path in yaml_files:
            try:
                with open(file_path, 'r', encoding='utf-8') as f:
                    if 'yaml-language-server' in f.read():
                        schema_files.append(file_path)
            except:
                continue

        return sorted(schema_files)

    def validate_path(self, path: str) -> Tuple[int, List[str]]:
        """Validate all files in the given path"""
        files = self.find_yaml_files_with_schemas(path)

        if not files:
            print(f"⚠️  No YAML files with schema annotations found in: {path}")
            return 0, []

        print(f"📊 Found {len(files)} files with schema annotations")

        total_mismatches = 0
        files_with_mismatches = []

        for file_path in files:
            mismatches = self.check_file_for_mismatches(file_path)
            if mismatches:
                print(f"\n❌ {file_path}")
                files_with_mismatches.append(file_path)
                for mismatch in mismatches:
                    print(f"   Document {mismatch['document']}: Schema version '{mismatch['schema_version']}' != API version '{mismatch['api_version_part']}' (from {mismatch['api_version']})")
                    print(f"   Current schema: {mismatch['schema_url']}")
                    if mismatch['expected_schema']:
                        print(f"   Expected schema: {mismatch['expected_schema']}")
                total_mismatches += len(mismatches)

        return total_mismatches, files_with_mismatches


def main():
    parser = argparse.ArgumentParser(
        description='Validate schema URL and apiVersion alignment in YAML files',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s                    # Check all files
  %(prog)s kubernetes/apps/   # Check specific directory
        """
    )
    parser.add_argument(
        'path',
        nargs='?',
        default='kubernetes',
        help='Path to directory or file to check (default: kubernetes)'
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
    validator = SchemaAlignmentValidator()

    print(f"🔍 Checking schema/apiVersion alignment in: {args.path}")
    print("=" * 60)

    # Validate files
    total_mismatches, files_with_mismatches = validator.validate_path(args.path)

    # Print summary
    print("\n" + "=" * 60)
    print("📊 Schema Alignment Summary")
    print(f"   Total mismatches: {total_mismatches}")
    print(f"   Files with issues: {len(files_with_mismatches)}")

    if total_mismatches == 0:
        print("\n✅ All schema URLs align with their apiVersions!")
        sys.exit(0)
    else:
        print(f"\n💥 Found {total_mismatches} schema/apiVersion mismatches in {len(files_with_mismatches)} files")
        print("\nTo fix these issues:")
        print("1. Update schema URLs to match the actual apiVersion")
        print("2. Or update apiVersion to match the schema")
        print("3. Ensure IDE validation works correctly")
        sys.exit(1)


if __name__ == "__main__":
    main()
