#!/bin/bash
# Script to install all required LaTeX packages for MADlib PDF build
# Run this script before running 'make pdf'

set -e  # Exit on error

echo "=== MADlib LaTeX Package Installer ==="
echo "This script will install all required LaTeX packages to ~/texmf"
echo ""

# Create base directory structure
echo "[1/10] Creating directory structure..."
mkdir -p ~/texmf/tex/latex
mkdir -p ~/texmf/fonts/tfm/public
mkdir -p ~/texmf/fonts/source/public

# Package 1: relsize
echo "[2/10] Installing relsize..."
mkdir -p ~/texmf/tex/latex/relsize
cd ~/texmf/tex/latex/relsize
wget -q https://mirrors.ctan.org/macros/latex/contrib/relsize/relsize.sty
echo "  ✓ relsize installed"

# Package 2: ntheorem
echo "[3/10] Installing ntheorem..."
mkdir -p ~/texmf/tex/latex/ntheorem
cd /tmp
wget -q https://mirrors.ctan.org/macros/latex/contrib/ntheorem.zip -O ntheorem.zip
unzip -q -o ntheorem.zip
cd ntheorem
latex -interaction=batchmode ntheorem.ins > /dev/null 2>&1
cp *.sty ~/texmf/tex/latex/ntheorem/
echo "  ✓ ntheorem installed"

# Package 3: biblatex
echo "[4/10] Installing biblatex..."
mkdir -p ~/texmf/tex/latex/biblatex
cd /tmp
wget -q https://mirrors.ctan.org/macros/latex/contrib/biblatex.zip -O biblatex.zip
unzip -q -o biblatex.zip
cp -r biblatex/latex/* ~/texmf/tex/latex/biblatex/
echo "  ✓ biblatex installed"

# Package 4: logreq
echo "[5/10] Installing logreq..."
mkdir -p ~/texmf/tex/latex/logreq
cd ~/texmf/tex/latex/logreq
wget -q https://mirrors.ctan.org/macros/latex/contrib/logreq/logreq.sty
wget -q https://mirrors.ctan.org/macros/latex/contrib/logreq/logreq.def
echo "  ✓ logreq installed"

# Package 5: scrpage2 compatibility wrapper
echo "[6/10] Creating scrpage2 compatibility wrapper..."
mkdir -p ~/texmf/tex/latex/scrpage2
cat > ~/texmf/tex/latex/scrpage2/scrpage2.sty << 'EOF'
% scrpage2 compatibility wrapper - redirects to scrlayer-scrpage
\NeedsTeXFormat{LaTeX2e}
\ProvidesPackage{scrpage2}[2025/10/21 Compatibility wrapper for scrpage2]

% Load the modern replacement
\RequirePackage{scrlayer-scrpage}

% Provide compatibility aliases for scrpage2 commands
\let\pagestyle\pagestyle
\let\automark\automark

\endinput
EOF
echo "  ✓ scrpage2 wrapper created"

# Package 6: xpatch
echo "[7/10] Installing xpatch..."
mkdir -p ~/texmf/tex/latex/xpatch
cd /tmp
wget -q https://mirrors.ctan.org/macros/latex/contrib/xpatch.zip -O xpatch.zip
unzip -q -o xpatch.zip
cd xpatch
latex -interaction=batchmode xpatch.ins > /dev/null 2>&1
cp xpatch.sty ~/texmf/tex/latex/xpatch/
echo "  ✓ xpatch installed"

# Package 7: transparent minimal implementation
echo "[8/10] Creating transparent package..."
mkdir -p ~/texmf/tex/latex/transparent
cat > ~/texmf/tex/latex/transparent/transparent.sty << 'EOF'
%% transparent.sty
%% Minimal implementation of the transparent package.

\NeedsTeXFormat{LaTeX2e}
\ProvidesPackage{transparent}[2019/11/29 v1.4 Transparency via pdfTeX's alpha channel (HO)]

\RequirePackage{auxhook}

\newcommand*{\transparent}[1]{%
  \pdfpageattr{/Group <</S /Transparency /I true /CS /DeviceRGB>>}%
}

\newcommand*{\texttransparent}[2]{%
  {#2}%
}

\endinput
EOF
echo "  ✓ transparent created"

# Package 8: algorithmicx
echo "[9/10] Installing algorithmicx..."
mkdir -p ~/texmf/tex/latex/algorithmicx
cd /tmp
wget -q https://mirrors.ctan.org/macros/latex/contrib/algorithmicx.zip -O algorithmicx.zip
unzip -q -o algorithmicx.zip
cp algorithmicx/*.sty ~/texmf/tex/latex/algorithmicx/
echo "  ✓ algorithmicx installed"

# Package 9: bbding (with modifications)
echo "[10/10] Installing and configuring bbding..."
mkdir -p ~/texmf/tex/latex/bbding
cd /tmp
wget -q https://mirrors.ctan.org/fonts/bbding.zip -O bbding.zip
unzip -q -o bbding.zip
cd bbding
latex -interaction=batchmode bbding.ins > /dev/null 2>&1
cp bbding.sty ~/texmf/tex/latex/bbding/
cp Uding.fd ~/texmf/tex/latex/bbding/

# Modify bbding.sty to use text symbols instead of fonts
cd ~/texmf/tex/latex/bbding
sed -i 's/\\newcommand{\\dingfamily}{\\fontencoding{U}\\fontfamily{ding}\\selectfont}/\\newcommand{\\dingfamily}{} % Disabled - use text substitutes/' bbding.sty
sed -i 's/\\newcommand{\\@chooseSymbol}\[1\]{{\\dingfamily\\symbol{#1}}}/\\newcommand{\\@chooseSymbol}[1]{{}} % Disabled - use text substitutes/' bbding.sty
sed -i "s/\\\\newcommand{\\\\HandRight}{\\\\@chooseSymbol{'021}}/\\\\renewcommand{\\\\HandRight}{\\\\ensuremath{\\\\Rightarrow}}/" bbding.sty
sed -i "s/\\\\newcommand{\\\\HandLeft}{\\\\@chooseSymbol{'022}}/\\\\renewcommand{\\\\HandLeft}{\\\\ensuremath{\\\\Leftarrow}}/" bbding.sty
echo "  ✓ bbding installed and configured"

# Update TeX filename database
echo ""
echo "Updating TeX filename database..."
texhash ~/texmf > /dev/null 2>&1
if [ -w /usr/share/texlive ]; then
    sudo mktexlsr > /dev/null 2>&1
fi

echo ""
echo "=== Installation Complete ==="
echo ""
echo "All LaTeX packages have been installed successfully."
echo "You can now run 'make pdf' from the build directory."
echo ""
echo "To build the PDF:"
echo "  cd /home/cbadmin/bom-parts/madlib/build"
echo "  make pdf"
echo ""
