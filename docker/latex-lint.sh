#!/bin/bash
# PENTeam LaTeX Lint Tool
# Validates LaTeX files for common errors before publication

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ERRORS=0
WARNINGS=0

log_error() {
    echo -e "${RED}ERROR:${NC} $1"
    ERRORS=$((ERRORS + 1))
}

log_warn() {
    echo -e "${YELLOW}WARNING:${NC} $1"
    WARNINGS=$((WARNINGS + 1))
}

log_info() {
    echo -e "${CYAN}INFO:${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

# Check for mismatched braces
check_braces() {
    local file="$1"
    local open=$(grep -o '{' "$file" | wc -l)
    local close=$(grep -o '}' "$file" | wc -l)
    
    if [ "$open" -ne "$close" ]; then
        log_error "Mismatched braces: $open opening, $close closing"
        return 1
    fi
    log_success "Braces: balanced ($open pairs)"
    return 0
}

# Check for mismatched environments
check_environments() {
    local file="$1"
    local line_num=0
    
    while IFS= read -r line; do
        line_num=$((line_num + 1))
        
        # Skip comments
        if [[ "$line" =~ ^\s*% ]]; then
            continue
        fi
        
        # Check for begin patterns
        if [[ "$line" =~ \\begin\{([^}]+)\} ]]; then
            env="${BASH_REMATCH[1]}"
            echo "$env" >> /tmp/latex_begin_stack.txt
        fi
        
        # Check for end patterns
        if [[ "$line" =~ \\end\{([^}]+)\} ]]; then
            env="${BASH_REMATCH[1]}"
            last_begin=$(tail -n1 /tmp/latex_begin_stack.txt 2>/dev/null || echo "")
            
            if [ -z "$last_begin" ]; then
                log_error "Line $line_num: \\end{$env} without matching \\begin"
            elif [ "$last_begin" != "$env" ]; then
                log_warn "Line $line_num: \\end{$env} may not match \\begin{$last_begin}"
            fi
            
            # Remove last begin from stack
            if [ -f /tmp/latex_begin_stack.txt ]; then
                head -n -1 /tmp/latex_begin_stack.txt > /tmp/latex_begin_stack_tmp.txt
                mv /tmp/latex_begin_stack_tmp.txt /tmp/latex_begin_stack.txt
            fi
        fi
    done < "$file"
    
    # Check for unclosed environments
    if [ -f /tmp/latex_begin_stack.txt ]; then
        local remaining=$(wc -l < /tmp/latex_begin_stack.txt)
        if [ "$remaining" -gt 0 ]; then
            log_error "Unclosed environments: $(cat /tmp/latex_begin_stack.txt | tr '\n' ', ')"
        fi
        rm -f /tmp/latex_begin_stack.txt
    fi
    
    return 0
}

# Check for unescaped underscores
check_underscores() {
    local file="$1"
    
    # Check for _ followed by letter (unescaped in text mode)
    local unescaped=$(grep -n '[^\]_[a-zA-Z]' "$file" | grep -v '^\s*%' | head -10 || true)
    
    if [ -n "$unescaped" ]; then
        log_warn "Possible unescaped underscores found (use \\_ in text mode):"
        echo "$unescaped" | while read -r line; do
            echo "  $line"
        done
    else
        log_success "Underscores: properly escaped"
    fi
}

# Check for unescaped percent
check_percent() {
    local file="$1"
    
    local unescaped=$(grep -n '^[^*]%' "$file" | grep -v '^\s*%' | head -5 || true)
    
    if [ -n "$unescaped" ]; then
        log_warn "Possible unescaped percent signs found (use \% in text mode):"
        echo "$unescaped" | while read -r line; do
            echo "  $line"
        done
    fi
}

# Check for required document structure
check_document_structure() {
    local file="$1"
    
    # Check for documentclass
    if ! grep -q '\\documentclass' "$file"; then
        log_error "Missing \\documentclass declaration"
    else
        log_success "Document class: present"
    fi
    
    # Check for document environment
    if ! grep -q '\\begin{document}' "$file"; then
        log_error "Missing \\begin{document} environment"
    else
        log_success "Document environment: present"
    fi
    
    if ! grep -q '\\end{document}' "$file"; then
        log_error "Missing \\end{document} environment"
    fi
    
    # Check for abstract
    if ! grep -q '\\begin{abstract}' "$file"; then
        log_warn "Missing abstract environment"
    else
        log_success "Abstract: present"
    fi
}

# Check for math mode issues
check_math_mode() {
    local file="$1"
    
    # Count display math delimiters
    local math_open=$(grep -o '\\\[' "$file" | wc -l)
    local math_close=$(grep -o '\\\]' "$file" | wc -l)
    
    if [ "$math_open" -ne "$math_close" ]; then
        log_error "Mismatched display math mode (\\[ count: $math_open, \\] count: $math_close)"
    else
        log_success "Display math: balanced ($math_open pairs)"
    fi
    
    # Check for inline math
    local inline_open=$(grep -o '\\(' "$file" | wc -l)
    local inline_close=$(grep -o '\\)' "$file" | wc -l)
    
    if [ "$inline_open" -ne "$inline_close" ]; then
        log_error "Mismatched inline math mode (count: open=$inline_open, close=$inline_close)"
    fi
}

# Check for common citation/reference issues
check_citations() {
    local file="$1"
    
    # Count citations
    local cite_count=$(grep -o '\\cite{' "$file" | wc -l)
    local bib_count=$(grep -o '\\bibitem{' "$file" | wc -l)
    
    if [ "$cite_count" -gt 0 ] && [ "$bib_count" -eq 0 ]; then
        if ! grep -q '\\bibliography{' "$file"; then
            log_warn "Citations used but no bibliography found"
        fi
    fi
    
    if [ "$bib_count" -gt 0 ]; then
        log_success "Bibliography: $bib_count entries"
    fi
    
    # Check for refs without labels
    local ref_count=$(grep -o '\\ref{' "$file" | wc -l)
    local label_count=$(grep -o '\\label{' "$file" | wc -l)
    
    if [ "$ref_count" -gt 0 ] && [ "$label_count" -eq 0 ]; then
        log_warn "References used but no labels found"
    fi
}

# Check for figure/table issues
check_floats() {
    local file="$1"
    
    # Check figures
    local fig_begin=$(grep -o '\\begin{figure}' "$file" | wc -l)
    local fig_end=$(grep -o '\\end{figure}' "$file" | wc -l)
    
    if [ "$fig_begin" -ne "$fig_end" ]; then
        log_error "Mismatched figure environments (begin: $fig_begin, end: $fig_end)"
    fi
    
    # Check tables
    local tab_begin=$(grep -o '\\begin{table}' "$file" | wc -l)
    local tab_end=$(grep -o '\\end{table}' "$file" | wc -l)
    
    if [ "$tab_begin" -ne "$tab_end" ]; then
        log_error "Mismatched table environments (begin: $tab_begin, end: $tab_end)"
    fi
}

# Check for LaTeX3 syntax issues
check_latex3() {
    local file="$1"
    
    # Check for _ in identifier names without proper delimiters
    if grep -q '__' "$file"; then
        log_info "LaTeX3 syntax detected (uses __ for private functions)"
    fi
}

# Main function
main() {
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           PENTeam LaTeX Lint Tool                        ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [ -z "$1" ]; then
        echo "Usage: $0 <latex-file>"
        echo ""
        echo "Validates LaTeX files for common errors before publication"
        exit 1
    fi
    
    local file="$1"
    
    if [ ! -f "$file" ]; then
        log_error "File not found: $file"
        exit 1
    fi
    
    echo -e "${CYAN}Checking:${NC} $file"
    echo ""
    
    # Run all checks
    check_document_structure "$file"
    check_braces "$file"
    check_environments "$file"
    check_math_mode "$file"
    check_underscores "$file"
    check_percent "$file"
    check_citations "$file"
    check_floats "$file"
    check_latex3 "$file"
    
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}Summary${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "  ${RED}Errors:${NC}   $ERRORS"
    echo -e "  ${YELLOW}Warnings:${NC} $WARNINGS"
    echo ""
    
    if [ $ERRORS -eq 0 ]; then
        echo -e "${GREEN}✓ LaTeX file passed basic validation${NC}"
        exit 0
    else
        echo -e "${RED}✗ LaTeX file has errors that need to be fixed${NC}"
        exit 1
    fi
}

main "$@"
