#!/bin/bash
set -e

echo "Installing workstreams CLI..."

# Build
npm install
npm run build

# Link globally
npm link

echo ""
echo "✅ Installed! The 'ws' command is now available."
echo ""
echo "Optional: Add shell integration to auto-detect projects on cd."
echo "Add this to your ~/.zshrc or ~/.bashrc:"
echo ""
echo '  # Workstreams shell integration'
echo '  ws_chpwd() {'
echo '    if command -v ws &>/dev/null && [ -d .git ]; then'
echo '      ws status 2>/dev/null || true'
echo '    fi'
echo '  }'
echo '  chpwd_functions=(${chpwd_functions[@]} "ws_chpwd")'
echo ""
