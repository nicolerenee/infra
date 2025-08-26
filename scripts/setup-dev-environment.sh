#!/usr/bin/env bash
set -euo pipefail

# Development Environment Setup Script
# This script sets up the development environment for the Kubernetes infrastructure repository

echo "🚀 Setting up development environment for Kubernetes infrastructure..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Check if running on macOS or Linux
OS="$(uname -s)"
case "${OS}" in
    Linux*)     MACHINE=Linux;;
    Darwin*)    MACHINE=Mac;;
    *)          MACHINE="UNKNOWN:${OS}"
esac

print_info "Detected OS: $MACHINE"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Install Homebrew on macOS
install_homebrew() {
    if [[ "$MACHINE" == "Mac" ]] && ! command_exists brew; then
        print_info "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        print_status "Homebrew installed"
    fi
}

# Install Task
install_task() {
    if ! command_exists task; then
        print_info "Installing Task..."
        if [[ "$MACHINE" == "Mac" ]]; then
            brew install go-task/tap/go-task
        elif [[ "$MACHINE" == "Linux" ]]; then
            sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d -b ~/.local/bin
            export PATH="$HOME/.local/bin:$PATH"
        fi
        print_status "Task installed"
    else
        print_status "Task already installed"
    fi
}

# Install Flux CLI
install_flux() {
    if ! command_exists flux; then
        print_info "Installing Flux CLI..."
        if [[ "$MACHINE" == "Mac" ]]; then
            brew install fluxcd/tap/flux
        elif [[ "$MACHINE" == "Linux" ]]; then
            curl -s https://fluxcd.io/install.sh | sudo bash
        fi
        print_status "Flux CLI installed"
    else
        print_status "Flux CLI already installed"
    fi
}

# Install kubectl
install_kubectl() {
    if ! command_exists kubectl; then
        print_info "Installing kubectl..."
        if [[ "$MACHINE" == "Mac" ]]; then
            brew install kubectl
        elif [[ "$MACHINE" == "Linux" ]]; then
            curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
            chmod +x kubectl
            sudo mv kubectl /usr/local/bin/
        fi
        print_status "kubectl installed"
    else
        print_status "kubectl already installed"
    fi
}

# Install yq
install_yq() {
    if ! command_exists yq; then
        print_info "Installing yq..."
        if [[ "$MACHINE" == "Mac" ]]; then
            brew install yq
        elif [[ "$MACHINE" == "Linux" ]]; then
            sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
            sudo chmod +x /usr/local/bin/yq
        fi
        print_status "yq installed"
    else
        print_status "yq already installed"
    fi
}

# Install Python dependencies
install_python_deps() {
    print_info "Installing Python dependencies..."
    
    # Check if pip3 is available
    if command_exists pip3; then
        pip3 install --user pyyaml jsonschema requests
        print_status "Python dependencies installed"
    elif command_exists pip; then
        pip install --user pyyaml jsonschema requests
        print_status "Python dependencies installed"
    else
        print_warning "pip not found. Please install Python dependencies manually:"
        print_info "pip3 install pyyaml jsonschema requests"
    fi
}

# Install pre-commit
install_precommit() {
    if ! command_exists pre-commit; then
        print_info "Installing pre-commit..."
        if command_exists pip3; then
            pip3 install --user pre-commit
        elif command_exists pip; then
            pip install --user pre-commit
        elif [[ "$MACHINE" == "Mac" ]]; then
            brew install pre-commit
        else
            print_warning "Could not install pre-commit. Please install manually."
            return
        fi
        print_status "pre-commit installed"
    else
        print_status "pre-commit already installed"
    fi
    
    # Install pre-commit hooks
    if [[ -f ".pre-commit-config.yaml" ]]; then
        print_info "Installing pre-commit hooks..."
        pre-commit install
        print_status "pre-commit hooks installed"
    fi
}

# Validate installation
validate_installation() {
    print_info "Validating installation..."
    
    local tools=("task" "flux" "kubectl" "yq" "python3")
    local missing_tools=()
    
    for tool in "${tools[@]}"; do
        if command_exists "$tool"; then
            print_status "$tool is available"
        else
            missing_tools+=("$tool")
            print_error "$tool is not available"
        fi
    done
    
    if [[ ${#missing_tools[@]} -eq 0 ]]; then
        print_status "All required tools are installed!"
    else
        print_error "Some tools are missing: ${missing_tools[*]}"
        print_info "Please install missing tools manually"
        return 1
    fi
}

# Test validation scripts
test_validation() {
    print_info "Testing validation scripts..."
    
    if [[ -f "scripts/validate-repository.py" ]]; then
        python3 scripts/validate-repository.py --structure --yaml
        print_status "Validation scripts are working"
    else
        print_warning "Validation scripts not found"
    fi
}

# Main installation process
main() {
    echo "=================================================="
    echo "🏗️  Kubernetes Infrastructure Dev Environment Setup"
    echo "=================================================="
    
    # Install tools based on OS
    if [[ "$MACHINE" == "Mac" ]]; then
        install_homebrew
    fi
    
    install_task
    install_flux
    install_kubectl
    install_yq
    install_python_deps
    install_precommit
    
    echo ""
    echo "=================================================="
    echo "🔍 Validation"
    echo "=================================================="
    
    validate_installation
    test_validation
    
    echo ""
    echo "=================================================="
    echo "🎉 Setup Complete!"
    echo "=================================================="
    
    print_status "Development environment is ready!"
    print_info "Next steps:"
    echo "  1. Run 'python3 scripts/validate-repository.py' to validate the repository"
    echo "  2. Use 'task --list' to see available automation tasks"
    echo "  3. Check 'CONTRIBUTING.md' for development guidelines"
    echo "  4. Run 'pre-commit run --all-files' to check code quality"
    
    if [[ "$MACHINE" == "Linux" ]]; then
        print_warning "You may need to add ~/.local/bin to your PATH"
        echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    fi
}

# Run main function
main "$@"
