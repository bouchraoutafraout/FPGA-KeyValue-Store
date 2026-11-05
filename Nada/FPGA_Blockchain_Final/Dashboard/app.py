"""Interface de supervision FPGA AC701 et de simulation RTL indépendante."""
from __future__ import annotations

import hashlib
import json
import re
import shutil
import subprocess
import tempfile
from datetime import datetime
from pathlib import Path

import pandas as pd
import streamlit as st

from fpga_uart import available_ports, exchange

ROOT = Path(__file__).resolve().parent
RTL = ROOT / "rtl"
TB = ROOT / "tb" / "dashboard_tb.v"
SOURCES = [RTL / "sha256_core.v", RTL / "block_hash.v", RTL / "chain_validator.v"]
DEFAULT_TX = ["07011234567800AA", "0703123456780055", "1122334455667788"]
SCENARIOS = {
    "Chaîne intacte": 0,
    "Transaction modifiée": 1,
    "Mauvais hash précédent": 2,
    "Hash stocké corrompu": 3,
}
TESTS = {
    "SHA-256 (abc + bloc 352 bits)": ("sha256_core_tb", ["sha256_core.v"]),
    "Block Hash (2 blocs)": ("block_hash_tb", ["sha256_core.v", "block_hash.v"]),
    "Chain Validator (5 scénarios)": ("chain_validator_tb", ["sha256_core.v", "chain_validator.v"]),
}


def normalize_hex(value: str) -> str:
    value = value.strip().removeprefix("0x").removeprefix("0X")
    if not re.fullmatch(r"[0-9a-fA-F]{1,16}", value):
        raise ValueError("Chaque transaction doit contenir de 1 à 16 chiffres hexadécimaux (64 bits maximum).")
    return value.upper().zfill(16)


def check_tools() -> tuple[str, str]:
    iverilog, vvp = shutil.which("iverilog"), shutil.which("vvp")
    if not iverilog or not vvp:
        raise RuntimeError(
            "Icarus Verilog est introuvable dans le PATH du processus Python. "
            "Ouvre le terminal MSYS2 UCRT64 (où 'iverilog -V' et 'vvp -V' fonctionnent), "
            "puis lance 'python -m streamlit run app.py' depuis ce même terminal."
        )
    return iverilog, vvp


def run_tools(top: str, files: list[Path], plusargs: list[str] | None = None) -> dict:
    iverilog, vvp = check_tools()
    for file in files:
        if not file.is_file():
            raise FileNotFoundError(f"Source absente : {file}")
    with tempfile.TemporaryDirectory(prefix="fpga_monitor_") as directory:
        work = Path(directory)
        simulator = work / "sim.out"
        compile_cmd = [iverilog, "-g2012", "-s", top, "-o", str(simulator), *map(str, files)]
        try:
            compiled = subprocess.run(compile_cmd, cwd=work, capture_output=True, text=True, timeout=40)
        except subprocess.TimeoutExpired as exc:
            raise RuntimeError("La compilation Verilog a dépassé 40 secondes.") from exc
        if compiled.returncode != 0:
            raise RuntimeError("Compilation Icarus Verilog échouée :\n" + compiled.stdout + "\n" + compiled.stderr)
        sim_cmd = [vvp, str(simulator), *(plusargs or [])]
        try:
            simulated = subprocess.run(sim_cmd, cwd=work, capture_output=True, text=True, timeout=40)
        except subprocess.TimeoutExpired as exc:
            raise RuntimeError("La simulation a dépassé 40 secondes.") from exc
        if simulated.returncode != 0:
            raise RuntimeError("Erreur d'exécution de la simulation :\n" + simulated.stdout + "\n" + simulated.stderr)
        vcd_files = list(work.glob("*.vcd"))
        vcd = vcd_files[0].read_bytes() if vcd_files else None
        return {
            "log": simulated.stdout,
            "stderr": compiled.stderr + simulated.stderr,
            "vcd": vcd,
            "timestamp": datetime.now().astimezone().isoformat(timespec="seconds"),
        }


def decode_trace(log: str) -> list[dict]:
    blocks: list[dict] = []
    for line in log.splitlines():
        if not line.startswith("DASH|BLOCK|"):
            continue
        parts = line.split("|")
        if len(parts) != 12:
            raise ValueError(f"Trace Verilog inattendue : {line}")
        _, _, number, tx, prev, stored, computed, expected, link, hash_ok, valid, cycles = parts
        if not all(re.fullmatch(r"[0-9a-fA-F]+", x) for x in [tx, prev, stored, computed, expected]):
            raise ValueError("Un hash n'est pas entièrement défini : simulation non fiable.")
        idx = int(number)
        if idx != len(blocks):
            raise ValueError("Les traces de blocs n'arrivent pas dans l'ordre attendu.")
        expected_sha_python = hashlib.sha256(
            idx.to_bytes(4, "big") + bytes.fromhex(prev) + bytes.fromhex(tx)
        ).hexdigest()
        block = {
            "index": idx,
            "transaction": tx.lower(),
            "previous_hash": prev.lower(),
            "expected_previous_hash": expected.lower(),
            "stored_hash": stored.lower(),
            "computed_hash": computed.lower(),
            "sha256_python": expected_sha_python,
            "link_ok": link == "1",
            "hash_ok": hash_ok == "1",
            "chain_valid": valid == "1",
            "sha_python_equal": computed.lower() == expected_sha_python,
            "cycles": int(cycles),
        }
        # Ne pas masquer un probleme du banc de test ou du RTL.
        if block["link_ok"] != (block["previous_hash"] == block["expected_previous_hash"]):
            raise ValueError(f"Incohérence du signal link_ok au bloc {idx}.")
        if block["hash_ok"] != (block["computed_hash"] == block["stored_hash"]):
            raise ValueError(f"Incohérence du signal hash_ok au bloc {idx}.")
        if block["chain_valid"] != (block["link_ok"] and block["hash_ok"]):
            raise ValueError(f"Incohérence du signal chain_valid au bloc {idx}.")
        blocks.append(block)
    if len(blocks) != 3 or "DASH|END|3|" not in log or "DASH|ERROR|" in log:
        raise ValueError("Simulation incomplète : il faut trois blocs et le marqueur de fin.\n" + log[-1500:])
    return blocks


def simulate(transactions: list[str], scenario: int, target: int) -> dict:
    args = [f"+SCENARIO={scenario}", f"+TARGET={target}"] + [
        f"+TX{i}={tx}" for i, tx in enumerate(transactions)
    ]
    output = run_tools("dashboard_tb", [TB, *SOURCES], args)
    output["blocks"] = decode_trace(output["log"])
    output["scenario"] = scenario
    output["target"] = target
    output["transactions_initiales"] = transactions
    return output


def label_hash(value: str) -> str:
    return value[:10] + "…" + value[-10:]



# Dashboard V2: VRAIE liaison du validateur -> builder -> SHA -> stockage -> validateur de chaine.
PIPE_SOURCES = [
    RTL / "transaction_validator.v",
    RTL / "blockchain_pipeline_top.v",
    RTL / "block_builder.v",
    RTL / "sha256_core.v",
    RTL / "blockchain_storage_adapter.v",
    RTL / "blockchain_storage.v",
    RTL / "chain_validator.v",
]
PIPE_TB = ROOT / "tb" / "pipeline_dashboard_tb.v"
OPERATIONS = ["CREATE", "SEARCH", "TRANSFER", "UNKNOWN"]
OP_CODES = {"CREATE": 1, "SEARCH": 2, "TRANSFER": 3, "UNKNOWN": 9}


def build_payload(operation: str, key_text: str, value_text: str) -> str:
    key_text = key_text.strip().removeprefix("0x").removeprefix("0X")
    value_text = value_text.strip().removeprefix("0x").removeprefix("0X")
    if not re.fullmatch(r"[0-9A-Fa-f]{1,8}", key_text):
        raise ValueError("Clé invalide : 1 à 8 caractères hexadécimaux.")
    if not re.fullmatch(r"[0-9A-Fa-f]{1,4}", value_text):
        raise ValueError("Valeur invalide : 1 à 4 caractères hexadécimaux.")
    return f"00{OP_CODES[operation]:02X}{int(key_text,16):08X}{int(value_text,16):04X}"


def run_pipeline(tx_list: list[str]) -> dict:
    args = [f"+N={len(tx_list)}"] + [f"+TX{i}={tx}" for i, tx in enumerate(tx_list)]
    result = run_tools("pipeline_dashboard_tb", [PIPE_TB, *PIPE_SOURCES], args)
    transactions = {}
    blocks = {}
    validations = {}
    final = None
    for line in result["log"].splitlines():
        if line.startswith("PIPE|FAIL|"):
            raise ValueError("Erreur matérielle simulée : " + line)
        p=line.strip().split("|")
        if len(p) >= 3 and p[0] == "PIPE":
            if p[1] == "TX" and len(p) == 12:
                step=int(p[2]); transactions[step]={
                    "étape":step+1, "type":int(p[3],16), "clé":p[4], "valeur":p[5],
                    "found":p[6]=="1", "error":p[7]=="1", "code":int(p[8]),
                    "valeur_lue":p[9], "acceptée":p[10]=="1", "blocs_stockés":int(p[11])}
            elif p[1] == "BLOCK" and len(p) == 8:
                step=int(p[2]); idx=int(p[3]); payload=p[4].lower(); prev=p[5].lower(); stored=p[6].lower()
                ref_hash=hashlib.sha256(idx.to_bytes(4,"big") + bytes.fromhex(prev) + bytes.fromhex(payload)).hexdigest()
                blocks[step]={"étape":step+1, "index":idx,"transaction":payload,
                    "previous_hash":prev,"sha256_rtl":stored,"sha256_python":ref_hash,
                    "concordance_sha":stored==ref_hash,"stockage_ok":p[7]=="1"}
            elif p[1] == "VERIFY" and len(p) == 7:
                step=int(p[2]); validations[step]={"link_ok":p[3]=="1","hash_ok":p[4]=="1",
                   "chain_valid":p[5]=="1", "computed_hash":p[6].lower()}
            elif p[1] == "END" and len(p) == 5:
                final=p
    if final is None or final[2]!="PASS" or int(final[3])!=len(tx_list):
        raise ValueError("Simulation non confirmée PASS ou incomplète.\n"+result["log"][-1400:])
    if len(transactions)!=len(tx_list):
        raise ValueError("Transactions manquantes dans les traces de la simulation.")
    if len(blocks)!=sum(t["acceptée"] for t in transactions.values()):
        raise ValueError("Nombre de blocs incohérent avec les transactions acceptées.")
    if len(validations)!=len(blocks):
        raise ValueError("Résultats Chain Validator incomplets.")
    result["tx"]=[transactions[i] for i in sorted(transactions)]
    result["blocks"]=[{**blocks[i],**validations[i]} for i in sorted(blocks)]
    result["sha_ok"]=all(b["concordance_sha"] and b["chain_valid"] and b["stockage_ok"] for b in result["blocks"])
    result["input"] = tx_list
    return result


st.set_page_config(page_title="FPGA Blockchain Monitor", layout="wide", initial_sidebar_state="collapsed")
st.markdown("""
<style>
:root { --monitor-accent: #3568a8; }
.block-title {font-weight:650;font-size:1.05rem;}
pre {white-space:pre-wrap;overflow-wrap:anywhere;}
[data-testid="stAppViewContainer"] > .main {background:transparent;}
[data-testid="stMetric"] {padding: .65rem .9rem; border:1px solid rgba(128,142,160,.22); border-radius:10px;}
div[data-testid="stTabs"] button {font-weight:550;}
</style>
""", unsafe_allow_html=True)

st.title("FPGA Blockchain Monitor")
st.caption("Supervision matérielle AC701 et validation RTL — résultats matériels et simulations présentés séparément")

with st.sidebar:
    st.header("Paramètres de simulation")
    with st.form("config"):
        scenario_name = st.radio("Scénario", list(SCENARIOS), index=0)
        target = st.selectbox("Bloc à modifier", [0, 1, 2], index=1,
                              help="Ignoré pour le scénario 'Chaîne intacte'.")
        st.markdown("**Transactions (64 bits hexadécimaux)**")
        values = [st.text_input(f"Bloc {i}", value=DEFAULT_TX[i], max_chars=18)
                  for i in range(3)]
        submit = st.form_submit_button("Exécuter la simulation RTL", type="primary", use_container_width=True)
    st.divider()
    st.caption("Ces paramètres concernent uniquement la simulation RTL et ne modifient pas le FPGA.")

if submit:
    try:
        tx_list = [normalize_hex(x) for x in values]
        with st.spinner("Compilation et exécution Icarus Verilog..."):
            st.session_state["simulation"] = simulate(tx_list, SCENARIOS[scenario_name], target)
        st.session_state.pop("sim_error", None)
    except Exception as exc:
        st.session_state.pop("simulation", None)
        st.session_state["sim_error"] = str(exc)

if "sim_error" in st.session_state:
    st.error(st.session_state["sim_error"])

fpga_tab, pipe_tab, sim_tab, test_tab = st.tabs(["FPGA réel", "Transactions RTL", "Intégrité simulée", "Tests unitaires"])

with pipe_tab:
    st.subheader("Simuler les transactions, les valider et créer les blocs")
    st.caption("Simulation RTL : validation des transactions, construction des blocs, SHA-256, stockage simulé et contrôle de chaîne. Le KVS simulé est simplifié et ne représente pas le matériel AC701.")
    examples=[("CREATE","11111111","00AA"),("SEARCH","11111111","0000"),
              ("TRANSFER","11111111","0055"),("CREATE","11111111","0001"),
              ("SEARCH","11111111","0000"),("SEARCH","99999999","0000")]
    with st.form("pipeline_form"):
        n=st.slider("Nombre de commandes",1,6,5)
        st.markdown("**Valeurs en hexadécimal** (clé 32 bits, valeur 16 bits)")
        commands=[]
        for i in range(n):
            col_op,col_key,col_val=st.columns([2,3,2])
            op=col_op.selectbox(f"Commande {i+1}",OPERATIONS,index=OPERATIONS.index(examples[i][0]),key=f"op_{i}")
            key=col_key.text_input(f"Clé {i+1}",value=examples[i][1],key=f"key_{i}")
            value=col_val.text_input(f"Valeur {i+1}",value=examples[i][2],key=f"value_{i}")
            commands.append((op,key,value))
        run=st.form_submit_button("Exécuter les transactions RTL",type="primary",use_container_width=True)
    if run:
        try:
            payloads=[build_payload(op,k,v) for op,k,v in commands]
            with st.spinner("Validation, SHA-256 et BRAM simulés par Icarus Verilog..."):
                st.session_state["pipeline_result"]=run_pipeline(payloads)
            st.session_state.pop("pipeline_error",None)
        except Exception as exc:
            st.session_state.pop("pipeline_result",None)
            st.session_state["pipeline_error"]=str(exc)
    if "pipeline_error" in st.session_state:
        st.error(st.session_state["pipeline_error"])
    result=st.session_state.get("pipeline_result")
    if result is None:
        st.info("Clique sur le bouton pour exécuter une vraie simulation Verilog. Aucun résultat n'est pré-calculé.")
    else:
        events=result["tx"]; blocks=result["blocks"]
        a,b,c,d=st.columns(4)
        a.metric("Commandes",len(events))
        b.metric("Transactions acceptées",sum(x["acceptée"] for x in events))
        c.metric("Commandes sans bloc",sum(not x["acceptée"] for x in events))
        d.metric("Blocs stockés",len(blocks))
        if result["sha_ok"]:
            st.success("Tous les blocs créés sont stockés, validés par le Chain Validator et leur SHA-256 concorde avec Python.")
        else:
            st.error("Un bloc a échoué : stockage, chaîne ou SHA-256 indépendant non concordant.")
        st.markdown("**1. Validation des commandes (RTL)**")
        st.dataframe(pd.DataFrame(events),hide_index=True,use_container_width=True)
        st.caption("Code de refus : R1=1 type, R2=2 clé nulle, R3=3 valeur, R4=4 clé existante, R5=5 clé absente, R6=6 KVS, R7=7 timeout. SEARCH ne crée pas de bloc.")
        st.markdown("**2. Blocs créés et vérifiés**")
        if not blocks: st.info("Aucun bloc créé par ces commandes.")
        else:
            cols=st.columns(min(3,len(blocks)))
            for i,bl in enumerate(blocks):
                with cols[i%len(cols)]:
                    with st.container(border=True):
                        st.markdown(f"**Bloc {bl['index']}**")
                        st.caption(f"Commande #{bl['étape']}")
                        st.code(bl['transaction'],language=None)
                        st.caption("SHA-256 (Verilog)")
                        st.code(label_hash(bl['sha256_rtl']),language=None)
                        st.write("Chaîne valide" if bl["chain_valid"] else "Chaîne invalide")
            select=st.selectbox("Détails cryptographiques",list(range(len(blocks))),format_func=lambda i:f"Bloc {blocks[i]['index']}")
            selected=blocks[select]
            for label,key in [("Hash précédent","previous_hash"),("Hash stocké (RTL)","sha256_rtl"),("SHA-256 indépendant (Python)","sha256_python")]:
                st.caption(label);st.code(selected[key],language=None)
            st.dataframe(pd.DataFrame([{k:v for k,v in b.items() if k not in ("sha256_rtl","sha256_python","previous_hash","transaction","computed_hash")} for b in blocks]),hide_index=True,use_container_width=True)
        st.markdown("**3. Preuves de simulation**")
        downloads=st.columns(3)
        payload={k:v for k,v in result.items() if k!="vcd"}
        downloads[0].download_button("Exporter JSON",json.dumps(payload,ensure_ascii=False,indent=2),"pipeline_transactions.json",mime="application/json")
        downloads[1].download_button("Exporter CSV",pd.DataFrame(events).to_csv(index=False),"transactions.csv",mime="text/csv")
        if result.get("vcd"):
            downloads[2].download_button("Exporter VCD",result["vcd"],"pipeline_dashboard.vcd",mime="application/octet-stream")
        with st.expander("Journal Icarus Verilog (source des résultats)"):
            st.code(result["log"],language="text")
            if result["stderr"]:st.code(result["stderr"],language="text")
        st.caption("Ce test utilise un banc d'essai et un KVS simplifié. Il ne démontre pas encore le Cuckoo réel, l'UART ni l'exécution physique FPGA.")

with sim_tab:
    data = st.session_state.get("simulation")
    if data is None:
        st.info("Choisis un scénario dans la barre latérale puis clique sur **Lancer la simulation Verilog**. Aucun résultat n'est affiché avant une vraie exécution.")
        st.markdown("**Scénarios disponibles :** chaîne saine ; transaction modifiée ; mauvais `previous_hash` ; hash stocké corrompu.")
    else:
        blocks = data["blocks"]
        valid_count = sum(b["chain_valid"] for b in blocks)
        invalid_count = 3 - valid_count
        refs_ok = sum(b["sha_python_equal"] for b in blocks)
        a, b, c, d = st.columns(4)
        a.metric("Blocs simulés", "3")
        b.metric("Blocs valides (RTL)", valid_count)
        c.metric("Anomalies détectées", invalid_count)
        d.metric("SHA-256 concordants", f"{refs_ok}/3")

        if data["scenario"] == 0:
            if valid_count == 3 and refs_ok == 3:
                st.success("Chaîne valide : les trois blocs ont été acceptés par le Chain Validator et leurs SHA-256 concordent avec Python.")
            else:
                st.error("Le scénario sain contient un échec à analyser dans les traces.")
        else:
            target_block = blocks[data["target"]]
            expected_flags = {1: (True, False), 2: (False, True), 3: (True, False)}
            expected = expected_flags[data["scenario"]]
            detected = (not target_block["chain_valid"] and
                        (target_block["link_ok"], target_block["hash_ok"]) == expected and
                        refs_ok == 3)
            if detected:
                st.success(f"Anomalie correctement détectée au bloc {data['target']} : le circuit a refusé ce bloc, conformément au scénario choisi.")
            else:
                st.error("Le circuit ne présente pas les signaux attendus pour le scénario : examiner les détails et les logs.")

        st.subheader("Chaîne simulée")
        cols = st.columns(3)
        for i, block in enumerate(blocks):
            with cols[i]:
                with st.container(border=True):
                    st.markdown(f"<div class='block-title'>Bloc {i}</div>", unsafe_allow_html=True)
                    st.markdown("**VALID**" if block["chain_valid"] else "**INVALID**")
                    st.caption("Transaction")
                    st.code("0x" + block["transaction"], language=None)
                    st.caption("Hash précédent")
                    st.code(label_hash(block["previous_hash"]), language=None)
                    st.caption("SHA-256 calculé (RTL)")
                    st.code(label_hash(block["computed_hash"]), language=None)
                    st.caption(f"Link : {'OK' if block['link_ok'] else 'ERREUR'}  ·  Hash : {'OK' if block['hash_ok'] else 'ERREUR'}")
                    st.caption(f"Validation : {block['cycles']} cycles simulés")
            if i < 2:
                pass  # Les trois colonnes suivent l'ordre 0 -> 1 -> 2.
        st.caption("Lecture de gauche à droite : Bloc 0 → Bloc 1 → Bloc 2. Les hexadécimaux complets figurent ci-dessous.")

        st.subheader("Détails des signaux du Chain Validator")
        table = pd.DataFrame([
            {"Bloc": x["index"], "Lien correct": x["link_ok"],
             "Hash correct": x["hash_ok"], "Bloc valide": x["chain_valid"],
             "SHA Python = RTL": x["sha_python_equal"], "Cycles": x["cycles"]}
            for x in blocks
        ])
        st.dataframe(table, hide_index=True, use_container_width=True)
        st.bar_chart(pd.DataFrame({"Cycles": [b["cycles"] for b in blocks]}, index=["Bloc 0", "Bloc 1", "Bloc 2"]))

        selected = st.selectbox("Inspecter les 256 bits d'un bloc", options=[0, 1, 2])
        one = blocks[selected]
        for title, key in [
            ("Transaction", "transaction"),
            ("previous_hash reçu", "previous_hash"),
            ("previous_hash attendu", "expected_previous_hash"),
            ("Hash stocké", "stored_hash"),
            ("SHA-256 recalculé par le FPGA simulé", "computed_hash"),
            ("SHA-256 indépendant (hashlib Python)", "sha256_python"),
        ]:
            st.caption(title)
            st.code(one[key], language=None)

        st.subheader("Exporter la preuve de simulation")
        exportable = {key: value for key, value in data.items() if key != "vcd"}
        exp1, exp2, exp3 = st.columns(3)
        with exp1:
            st.download_button("Exporter JSON", json.dumps(exportable, indent=2, ensure_ascii=False),
                               file_name="resultats_fpga_blockchain.json", mime="application/json")
        with exp2:
            st.download_button("Exporter CSV", pd.DataFrame(blocks).to_csv(index=False),
                               file_name="resultats_fpga_blockchain.csv", mime="text/csv")
        with exp3:
            if data.get("vcd"):
                st.download_button("Exporter VCD", data["vcd"],
                                   file_name="blockchain_dashboard.vcd", mime="application/octet-stream")
        with st.expander("Afficher la sortie originale de vvp (preuve brute)"):
            st.code(data["log"], language="text")
            if data["stderr"]:
                st.caption("Avertissements du compilateur/simulateur")
                st.code(data["stderr"], language="text")
        st.caption(f"Simulation locale exécutée le {data['timestamp']}. Les cycles sont mesurés en simulation, et non sur le FPGA physique.")

with test_tab:
    st.write("Ces tests sont les **testbenches originaux** présents dans votre dernière archive du projet.")
    test_name = st.selectbox("Choisir un test", list(TESTS))
    if st.button("Exécuter le test unitaire", use_container_width=False):
        top, source_names = TESTS[test_name]
        test_sources = [ROOT / "tests" / (top + ".v")] + [RTL / n for n in source_names]
        try:
            with st.spinner("Simulation du testbench original..."):
                result = run_tools(top, test_sources)
            lines = result["log"].splitlines()
            passed = [line for line in lines if line.strip().startswith("PASS :")]
            failed = [line for line in lines if line.strip().startswith("FAIL :")]
            st.session_state["unit_result"] = (test_name, result, passed, failed)
        except Exception as exc:
            st.session_state["unit_result"] = (test_name, {"log": str(exc), "stderr": "", "vcd": None}, [], ["Erreur de simulation"])
    if "unit_result" in st.session_state:
        which, res, passes, fails = st.session_state["unit_result"]
        st.caption(f"Dernier test exécuté : {which}")
        if passes and not fails:
            st.success(f"{len(passes)} ligne(s) PASS, 0 ligne FAIL")
        else:
            st.error(f"{len(passes)} PASS et {len(fails)} FAIL : vérifier la sortie.")
        st.code(res["log"], language="text")
        if res.get("stderr"):
            st.code(res["stderr"], language="text")
        if res.get("vcd"):
            st.download_button("Télécharger le VCD du test", res["vcd"], "test_original.vcd")


with fpga_tab:
    st.subheader("Console matérielle — AC701")
    st.caption("UART 115200 bauds, 8N1. Requête ASCII terminée par CR ; réponse terminée par CRLF. Les réponses de cet onglet proviennent du FPGA connecté.")

    ports = available_ports()
    if not ports:
        st.warning("Aucun port série détecté. Vérifiez le câble USB-UART et le gestionnaire de périphériques.")
    default_port = "COM4" if "COM4" in ports else (ports[0] if ports else "COM4")

    with st.container(border=True):
        with st.form("fpga_uart_form", clear_on_submit=False):
            c_port, c_baud = st.columns([3, 1])
            port = c_port.text_input("Port série", value=default_port).strip()
            baud = c_baud.number_input("Débit (bauds)", min_value=1200, max_value=3000000, value=115200, step=100)
            c_op, c_key, c_val, c_idx = st.columns([2, 2.5, 2, 1.3])
            operation = c_op.selectbox("Opération", ["CREATE", "SEARCH", "TRANSFER", "VERIFY", "PING"], index=0)
            key = c_key.text_input("Clé (hex, 32 bits)", value="00000001", help="Utilisée pour CREATE, SEARCH et TRANSFER")
            value = c_val.text_input("Valeur (hex, 16 bits)", value="0064", help="Utilisée pour CREATE et TRANSFER")
            verify_index = c_idx.number_input("Index du bloc", min_value=0, max_value=15, value=0, step=1,
                                               help="Utilisé seulement pour VERIFY")
            send = st.form_submit_button("Envoyer la commande", type="primary", use_container_width=True)
    st.caption("Pour VERIFY, choisissez l'index du bloc. Les champs clé et valeur sont ignorés. Une seule connexion à COM4 est ouverte par commande puis refermée.")

    if send:
        try:
            result = exchange(port=port, operation=operation, key=key, value=value,
                              verify_index=int(verify_index), baudrate=int(baud))
            st.session_state.setdefault("fpga_uart_history", []).append(result)
            st.session_state["fpga_uart_last"] = result
            st.session_state.pop("fpga_uart_error", None)
        except Exception as exc:
            st.session_state["fpga_uart_error"] = str(exc)
            st.session_state.pop("fpga_uart_last", None)

    if "fpga_uart_error" in st.session_state:
        st.error(st.session_state["fpga_uart_error"])

    result = st.session_state.get("fpga_uart_last")
    if result:
        st.markdown("#### Dernier échange matériel")
        if result["kind"] == "valid":
            st.success("VALID — bloc accepté par le vérificateur matériel.")
        elif result["kind"] == "invalid":
            st.error("INVALID — le vérificateur a rejeté le bloc.")
        elif result["kind"] == "verification_error":
            st.warning("ERRVERIFY — vérification impossible ou erreur signalée par le FPGA.")
        elif result["success"]:
            st.success("Commande exécutée : " + result["response"])
        else:
            st.error("Commande non confirmée : " + result["response"])
        c1, c2 = st.columns(2)
        c1.metric("Commande transmise", result["command"])
        c2.metric("Réponse UART", result["response"])
        if result["kind"] == "found":
            st.write(f"Valeur lue : **{result['value']}** (décimal) / **{result['value']:04X}** (hexadécimal)")
        with st.expander("Détails UART (trames hexadécimales)"):
            st.code("TX : " + result["sent_hex"] + "\nRX : " + result["received_hex"], language="text")

    history = st.session_state.get("fpga_uart_history", [])
    st.markdown("#### Historique des opérations")
    if history:
        rows = [{"Date": x["timestamp"], "Port": x["port"], "Opération": x["operation"],
                 "Commande": x["command"], "Réponse": x["response"],
                 "Statut": "Succès" if x["success"] else "Contrôle requis"} for x in history]
        st.dataframe(pd.DataFrame(rows), hide_index=True, use_container_width=True)
        a, b = st.columns([2, 1])
        a.download_button("Exporter l'historique (JSON)", json.dumps(history, indent=2, ensure_ascii=False),
                          file_name="fpga_uart_history.json", mime="application/json", use_container_width=True)
        if b.button("Effacer l'historique", use_container_width=True):
            st.session_state.pop("fpga_uart_history", None)
            st.session_state.pop("fpga_uart_last", None)
            st.rerun()
    else:
        st.caption("Aucune transaction dans cette session.")
    st.caption("Le protocole UART ne fournit pas directement le contenu intégral des blocs ni leurs hashes. Les résultats des autres onglets proviennent de simulations sur ordinateur.")
