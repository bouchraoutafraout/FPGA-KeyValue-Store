#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
if ! command -v iverilog >/dev/null || ! command -v vvp >/dev/null; then
    echo "ERREUR: Icarus Verilog introuvable. Lance ce script depuis MSYS2 UCRT64."
    exit 1
fi
if ! command -v python >/dev/null; then
    echo "ERREUR: Python introuvable. Installe Python 3 et pip."
    exit 1
fi
if ! python -c 'import streamlit, pandas' 2>/dev/null; then
    echo "Modules Python manquants. Exécute d'abord : python -m pip install -r requirements.txt"
    exit 1
fi
python -m streamlit run app.py
