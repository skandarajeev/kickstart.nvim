#!/usr/bin/env sh

# Stop immediately when:
#   - A command fails
#   - An undefined variable is used
set -eu

# Git repository containing the Neovim configuration.
REPO="https://github.com/skandarajeev/kickstart.nvim.git"

# Branch containing the configuration that should be installed.
BRANCH="skanda"

# Neovim's standard configuration directory.
#
# If XDG_CONFIG_HOME is configured, use it.
# Otherwise, use ~/.config/nvim.
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"


# Run a command as root.
#
# If the script is already running as root, run the command normally.
# Otherwise, use sudo.
run_as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    echo "Error: sudo is required to install system files." >&2
    exit 1
  fi
}


# Install the latest stable Neovim release on Linux.
#
# This downloads Neovim directly from its official GitHub releases.
# It avoids older Neovim versions that may exist in Linux repositories.
install_linux_nvim() {
  # Select the correct Neovim download for the computer's CPU.
  case "$(uname -m)" in
    x86_64|amd64)
      nvim_archive="nvim-linux-x86_64"
      ;;

    aarch64|arm64)
      nvim_archive="nvim-linux-arm64"
      ;;

    *)
      echo "Error: unsupported CPU architecture: $(uname -m)" >&2
      exit 1
      ;;
  esac

  # Create a temporary directory for the download.
  nvim_tmp="$(mktemp -d)"

  echo "Downloading the latest stable Neovim..."

  # Download the latest stable Neovim tarball.
  curl -fsSL \
    "https://github.com/neovim/neovim/releases/latest/download/${nvim_archive}.tar.gz" \
    -o "$nvim_tmp/nvim.tar.gz"

  # Remove a previously installed copy.
  run_as_root rm -rf "/opt/$nvim_archive"

  # Extract Neovim into /opt.
  run_as_root tar \
    -C /opt \
    -xzf "$nvim_tmp/nvim.tar.gz"

  # Ensure /usr/local/bin exists.
  run_as_root mkdir -p /usr/local/bin

  # Make the `nvim` command available globally.
  run_as_root ln \
    -sf "/opt/$nvim_archive/bin/nvim" \
    /usr/local/bin/nvim

  # Remove the temporary download directory.
  rm -rf "$nvim_tmp"
}


# Install the latest official Tree-sitter CLI on Linux.
#
# Debian and Ubuntu often do not provide an APT package called
# `tree-sitter-cli`, so the official binary is downloaded instead.
install_linux_tree_sitter() {
  # Select the correct Tree-sitter download for the computer's CPU.
  case "$(uname -m)" in
    x86_64|amd64)
      tree_sitter_arch="x64"
      ;;

    aarch64|arm64)
      tree_sitter_arch="arm64"
      ;;

    *)
      echo "Error: unsupported CPU architecture: $(uname -m)" >&2
      exit 1
      ;;
  esac

  # Create a temporary directory for the download.
  tree_sitter_tmp="$(mktemp -d)"

  echo "Downloading the latest Tree-sitter CLI..."

  # Download the latest official Tree-sitter CLI ZIP archive.
  curl -fsSL \
    "https://github.com/tree-sitter/tree-sitter/releases/latest/download/tree-sitter-cli-linux-${tree_sitter_arch}.zip" \
    -o "$tree_sitter_tmp/tree-sitter.zip"

  # Extract the Tree-sitter executable.
  unzip \
    -q "$tree_sitter_tmp/tree-sitter.zip" \
    -d "$tree_sitter_tmp"

  # Ensure /usr/local/bin exists.
  run_as_root mkdir -p /usr/local/bin

  # Install the executable as /usr/local/bin/tree-sitter.
  run_as_root install \
    -m 755 \
    "$tree_sitter_tmp/tree-sitter" \
    /usr/local/bin/tree-sitter

  # Remove the temporary download directory.
  rm -rf "$tree_sitter_tmp"
}


echo "Installing Neovim and its dependencies..."


# Detect the operating system.
case "$(uname -s)" in
  Darwin)
    # macOS installation using Homebrew.
    if ! command -v brew >/dev/null 2>&1; then
      echo "Error: Homebrew is required on macOS." >&2
      echo "Install Homebrew and run this script again." >&2
      exit 1
    fi

    # Install Neovim and its required tools.
    brew install \
      neovim \
      git \
      make \
      ripgrep \
      fd \
      tree-sitter
    ;;


  Linux)
    # Debian, Ubuntu, Linux Mint, and Ubuntu through WSL.
    if command -v apt-get >/dev/null 2>&1; then
      run_as_root apt-get update

      # Install the basic tools required by the Neovim configuration.
      #
      # Tree-sitter CLI is intentionally not included here because the
      # package is unavailable in many Debian and Ubuntu repositories.
      run_as_root apt-get install -y \
        git \
        curl \
        make \
        gcc \
        g++ \
        tar \
        unzip \
        ripgrep \
        fd-find \
        xclip

      # Debian and Ubuntu call the fd executable `fdfind`.
      #
      # Create an `fd` command because Neovim plugins commonly expect it.
      if command -v fdfind >/dev/null 2>&1; then
        run_as_root mkdir -p /usr/local/bin

        run_as_root ln \
          -sf "$(command -v fdfind)" \
          /usr/local/bin/fd
      fi


    # Fedora and related Linux distributions.
    elif command -v dnf >/dev/null 2>&1; then
      run_as_root dnf install -y \
        git \
        curl \
        make \
        gcc \
        gcc-c++ \
        tar \
        unzip \
        ripgrep \
        fd-find \
        xclip


    # Arch Linux, Manjaro, EndeavourOS, and related distributions.
    elif command -v pacman >/dev/null 2>&1; then
      run_as_root pacman -Syu --noconfirm --needed \
        git \
        curl \
        base-devel \
        tar \
        unzip \
        ripgrep \
        fd \
        xclip


    # Stop when the Linux package manager is unsupported.
    else
      echo "Error: unsupported Linux package manager." >&2
      echo "Supported package managers: apt, dnf, and pacman." >&2
      exit 1
    fi

    # Install current official Neovim and Tree-sitter binaries.
    install_linux_nvim
    install_linux_tree_sitter
    ;;


  *)
    echo "Error: unsupported operating system." >&2
    echo "Supported systems: macOS and Linux, including Windows through WSL." >&2
    exit 1
    ;;
esac


# Create the parent configuration directory when necessary.
mkdir -p "$(dirname "$CONFIG_DIR")"


# Back up an existing Neovim configuration.
#
# The existing configuration is not deleted.
# Example backup:
#
# ~/.config/nvim.backup.20260713-143000
if [ -e "$CONFIG_DIR" ] || [ -L "$CONFIG_DIR" ]; then
  BACKUP_DIR="${CONFIG_DIR}.backup.$(date +%Y%m%d-%H%M%S)"

  echo "Existing Neovim configuration found."
  echo "Moving it to: $BACKUP_DIR"

  mv "$CONFIG_DIR" "$BACKUP_DIR"
fi


# Clone the `skanda` branch into Neovim's configuration directory.
echo "Installing the Neovim configuration..."

git clone \
  --depth 1 \
  --branch "$BRANCH" \
  "$REPO" \
  "$CONFIG_DIR"


# Print installed versions for troubleshooting.
echo
echo "Installed versions:"

nvim --version | head -n 1
tree-sitter --version


echo
echo "Installation completed successfully."
echo "Start Neovim with:"
echo
echo "  nvim"
