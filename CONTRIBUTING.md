# Contributing to Home Kubernetes Infrastructure

Thank you for your interest in contributing to this home lab infrastructure project! This repository serves as both a personal infrastructure setup and a reference implementation for others building similar GitOps-managed Kubernetes environments.

## 🤝 Ways to Contribute

### For Personal Use
- **Fork and Adapt**: Use this repository as a starting point for your own infrastructure
- **Share Improvements**: Submit PRs for general improvements that benefit everyone
- **Report Issues**: Open issues for bugs, questions, or suggestions

### For the Community
- **Documentation**: Improve README, add guides, or clarify configurations
- **Best Practices**: Share security, performance, or operational improvements
- **Bug Fixes**: Fix issues that affect the general setup
- **New Features**: Add useful tools or configurations

## 🚀 Getting Started

### Prerequisites
- **Kubernetes Knowledge**: Understanding of Kubernetes concepts and YAML
- **GitOps Familiarity**: Experience with Flux v2 or similar GitOps tools
- **Talos Linux**: Knowledge of Talos for cluster management (optional)

### Development Environment
1. **Fork the repository** to your GitHub account
2. **Clone your fork** locally
3. **Install dependencies**:
   ```bash
   # Install Task for automation
   brew install go-task/tap/go-task
   
   # Install Flux CLI
   brew install fluxcd/tap/flux
   
   # Install Python dependencies for validation
   pip3 install pyyaml jsonschema requests
   ```

### Validation Tools
This repository includes validation scripts to ensure quality:

```bash
# Validate Kustomization files
python3 scripts/validate-kustomizations.py

# Check schema/apiVersion alignment
python3 scripts/validate-schema-alignment.py

# Run all validations (if you have a local cluster)
task validate
```

## 📝 Making Changes

### Branch Naming
Use descriptive branch names:
- `feat/add-new-application`
- `fix/schema-validation-issue`
- `docs/improve-readme`
- `security/update-rbac-policies`

### Commit Messages
Follow conventional commit format:
```
feat: add new monitoring dashboard for storage metrics
fix: correct schema URL for external secrets
docs: add troubleshooting guide for flux issues
security: update RBAC permissions for service accounts
```

### File Organization
- **Applications**: Place new apps in `kubernetes/apps/<category>/`
- **Cluster-specific**: Use `kubernetes/clusters/<cluster-name>/apps/`
- **Reusable components**: Add to `kubernetes/components/`
- **Scripts**: Add utilities to `scripts/` directory

## 🔍 Code Quality

### YAML Standards
- **Indentation**: Use 2 spaces (no tabs)
- **Line Length**: Keep lines under 120 characters
- **Comments**: Add yaml-language-server schema annotations
- **Naming**: Use consistent, descriptive names

### Schema Validation
All YAML files should include appropriate schema annotations:
```yaml
# yaml-language-server: $schema=https://www.schemastore.org/kustomization.json
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
```

### Security Considerations
- **No Hardcoded Secrets**: Use External Secrets Operator
- **Least Privilege**: Apply minimal RBAC permissions
- **Security Contexts**: Avoid running as root when possible
- **Network Policies**: Consider network segmentation

## 🧪 Testing

### Local Validation
Before submitting PRs, run local validation:
```bash
# Validate all Kustomization files
python3 scripts/validate-kustomizations.py

# Check for schema mismatches
python3 scripts/validate-schema-alignment.py

# Test Kustomize builds (if you have kubectl)
find kubernetes -name kustomization.yaml -execdir kubectl kustomize . \;
```

### CI/CD Pipeline
The repository includes GitHub Actions that will:
- Validate YAML syntax and schemas
- Check Kustomization completeness
- Verify Flux compatibility
- Run security scans

## 📋 Pull Request Process

### Before Submitting
1. **Test locally** using validation scripts
2. **Update documentation** if adding new features
3. **Check for breaking changes** in existing deployments
4. **Verify schema annotations** are correct

### PR Description
Include in your PR description:
- **What**: Brief description of changes
- **Why**: Reason for the change
- **How**: Implementation approach
- **Testing**: How you validated the changes
- **Breaking Changes**: Any potential impacts

### Review Process
1. **Automated Checks**: CI/CD pipeline must pass
2. **Code Review**: Maintainer will review for quality and security
3. **Testing**: Changes may be tested in a staging environment
4. **Merge**: Approved changes will be merged and deployed

## 🔧 Common Tasks

### Adding a New Application
1. Create application directory: `kubernetes/apps/<category>/<app-name>/`
2. Add HelmRelease or raw manifests
3. Create Kustomization file
4. Add to cluster-specific apps if needed
5. Test with validation scripts

### Updating Dependencies
- **Renovate** handles most dependency updates automatically
- Manual updates should follow the same patterns
- Test updates in a non-production environment first

### Troubleshooting
- **Flux Issues**: Check `flux get all` and `flux logs`
- **Schema Errors**: Run validation scripts for detailed error messages
- **Deployment Issues**: Check pod logs and events

## 🛡️ Security

### Reporting Security Issues
- **Private Issues**: Email security concerns privately
- **Public Issues**: Use GitHub issues for general security improvements
- **Responsible Disclosure**: Allow time for fixes before public disclosure

### Security Best Practices
- Keep secrets in 1Password, not in YAML files
- Use minimal container privileges
- Apply network policies where appropriate
- Regularly update dependencies via Renovate

## 📚 Resources

### Documentation
- [Flux Documentation](https://fluxcd.io/docs/)
- [Kustomize Documentation](https://kustomize.io/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Talos Linux Documentation](https://www.talos.dev/docs/)

### Community
- **GitHub Discussions**: For questions and general discussion
- **Issues**: For bug reports and feature requests
- **Pull Requests**: For code contributions

## 🙏 Recognition

Contributors will be recognized in:
- Git commit history
- Release notes for significant contributions
- README acknowledgments for major features

Thank you for helping improve this infrastructure setup! 🚀
