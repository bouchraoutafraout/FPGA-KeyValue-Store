"""Interface UART ASCII du bitstream AC701 uart_blockchain_top.

Une transaction = 1 commande ASCII terminée par CR (0x0D).
La réponse du FPGA est terminée par CR/LF.
"""
from __future__ import annotations

import re
import time
from datetime import datetime

try:
    import serial
    from serial.tools import list_ports
except ImportError:
    serial = None
    list_ports = None


class FPGAUARTError(RuntimeError):
    pass


def available_ports() -> list[str]:
    if list_ports is None:
        return []
    return [p.device for p in list_ports.comports()]


def normalize_key(key: str) -> str:
    value = key.strip().removeprefix('0x').removeprefix('0X')
    if not re.fullmatch(r'[0-9a-fA-F]{1,8}', value):
        raise ValueError('Clé attendue : 1 à 8 chiffres hexadécimaux (32 bits).')
    return value.upper().zfill(8)


def normalize_value(value: str) -> str:
    value = value.strip().removeprefix('0x').removeprefix('0X')
    if not re.fullmatch(r'[0-9a-fA-F]{1,4}', value):
        raise ValueError('Valeur attendue : 1 à 4 chiffres hexadécimaux (16 bits).')
    return value.upper().zfill(4)


def normalize_verify_index(index: int | str) -> int:
    try:
        n = int(index)
    except (TypeError, ValueError) as exc:
        raise ValueError('Index de bloc invalide (0 à 15).') from exc
    if n < 0 or n > 15:
        raise ValueError('Index de bloc hors plage (0 à 15).')
    return n


def build_uart_command(operation: str, key: str = '1', value: str = '0', verify_index: int = 0) -> str:
    if operation == 'PING':
        return 'PING'
    if operation == 'VERIFY':
        return f'V{normalize_verify_index(verify_index):04X}'
    k = normalize_key(key)
    if operation == 'SEARCH':
        return 'S' + k
    if operation in {'CREATE', 'TRANSFER'}:
        return ('C' if operation == 'CREATE' else 'T') + k + normalize_value(value)
    raise ValueError(f'Commande UART non prise en charge : {operation}')


def parse_uart_response(operation: str, response: str) -> dict:
    response = response.strip().upper()
    if operation == 'PING' and response == 'PONG':
        return {'success': True, 'kind': 'pong', 'value': None}
    if operation in {'CREATE', 'TRANSFER'} and response == 'OK':
        return {'success': True, 'kind': 'ack', 'value': None}
    m = re.fullmatch(r'FOUND=([0-9A-F]{4})', response)
    if operation == 'SEARCH' and m:
        return {'success': True, 'kind': 'found', 'value': int(m.group(1), 16)}
    if operation == 'VERIFY':
        if response == 'VALID':
            return {'success': True, 'kind': 'valid', 'value': None}
        if response == 'INVALID':
            return {'success': False, 'kind': 'invalid', 'value': None}
        if response == 'ERRVERIFY':
            return {'success': False, 'kind': 'verification_error', 'value': None}
    if response.startswith('ERR') or response in {'NOTFOUND', 'NOT_FOUND'}:
        return {'success': False, 'kind': 'fpga_error', 'value': None}
    return {'success': False, 'kind': 'unexpected', 'value': None}


def exchange(port: str, operation: str, key: str = '1', value: str = '0',
             baudrate: int = 115200, timeout: float = 10.0,
             verify_index: int = 0) -> dict:
    """Open, send one CR-delimited request, read one CRLF-delimited response, close."""
    if serial is None:
        raise FPGAUARTError('pyserial absent. Exécuter : python -m pip install pyserial')
    if not port or not isinstance(port, str):
        raise ValueError('Sélectionner un port série valide.')
    if not 1200 <= baudrate <= 3000000:
        raise ValueError('Baudrate hors plage.')
    command = build_uart_command(operation, key, value, verify_index)
    sent = (command + '\r').encode('ascii')
    try:
        with serial.Serial(port=port, baudrate=baudrate, bytesize=serial.EIGHTBITS,
                           parity=serial.PARITY_NONE, stopbits=serial.STOPBITS_ONE,
                           timeout=0.15, write_timeout=2.0,
                           xonxoff=False, rtscts=False, dsrdtr=False) as conn:
            conn.reset_input_buffer()
            start = time.monotonic()
            conn.write(sent)
            conn.flush()
            received = bytearray()
            while time.monotonic() - start < timeout:
                b = conn.read(1)
                if not b:
                    continue
                received.extend(b)
                if len(received) > 256:
                    raise FPGAUARTError('Réponse UART trop longue (>256 octets).')
                if b == b'\n':
                    break
            else:
                if not received:
                    raise FPGAUARTError('Aucune réponse FPGA : vérifier COM, bitstream et câbles.')
                raise FPGAUARTError('Réponse incomplète (pas de fin CRLF) : ' + repr(bytes(received)))
    except (serial.SerialException, OSError) as exc:
        raise FPGAUARTError(f'Impossible de communiquer sur {port} : {exc}. Fermer PuTTY si ce port est ouvert.') from exc
    try:
        response = bytes(received).decode('ascii').strip('\r\n')
    except UnicodeDecodeError as exc:
        raise FPGAUARTError('Réponse non ASCII : vérifier les paramètres UART.') from exc
    return {'timestamp': datetime.now().astimezone().isoformat(timespec='seconds'),
            'port': port, 'baudrate': baudrate, 'operation': operation,
            'key': normalize_key(key) if operation in ('CREATE', 'TRANSFER', 'SEARCH') else None,
            'verify_index': normalize_verify_index(verify_index) if operation == 'VERIFY' else None,
            'value_sent': normalize_value(value) if operation in ('CREATE', 'TRANSFER') else None,
            'command': command, 'sent_hex': sent.hex(' ').upper(),
            'response': response, 'received_hex': bytes(received).hex(' ').upper(),
            **parse_uart_response(operation, response)}
