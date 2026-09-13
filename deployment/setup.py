#!/usr/bin/env python3
"""Local TLS sandbox only. Does not flash hardware or publish a public service."""
import os, secrets, subprocess, pathlib, sys, re
root=pathlib.Path(__file__).resolve().parent
private=root/'private'
if private.exists() or (root/'.env').exists():
    raise SystemExit('Existing setup found; refusing to replace keys or credentials.')
host=sys.argv[1] if len(sys.argv)>1 else 'localhost'
if not re.fullmatch(r'[a-zA-Z0-9.-]+',host): raise SystemExit('Invalid hostname')
os.umask(0o077);private.mkdir()
def run(*args): subprocess.run(args,check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
run('openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(private/'ca.key'),'-out',str(private/'ca.crt'),'-days','365','-subj','/CN=AiRobot local test CA')
run('openssl','req','-newkey','rsa:2048','-nodes','-keyout',str(private/'server.key'),'-out',str(private/'server.csr'),'-subj','/CN='+host)
(private/'server.ext').write_text('subjectAltName=DNS:localhost,DNS:broker,DNS:'+host+',IP:127.0.0.1\nextendedKeyUsage=serverAuth\n')
run('openssl','x509','-req','-in',str(private/'server.csr'),'-CA',str(private/'ca.crt'),'-CAkey',str(private/'ca.key'),'-CAcreateserial','-out',str(private/'server.crt'),'-days','90','-extfile',str(private/'server.ext'))
run('openssl','genpkey','-algorithm','RSA','-pkeyopt','rsa_keygen_bits:2048','-out',str(private/'signing.pem'))
run('openssl','pkey','-in',str(private/'signing.pem'),'-pubout','-out',str(private/'signing.pub'))
password=secrets.token_urlsafe(32)
env=dict(POSTGRES_PASSWORD=secrets.token_hex(24),AUTH_SECRET=secrets.token_hex(32),MQTT_ADMIN_PASSWORD=password,LOCAL_UID=str(os.getuid()),LOCAL_GID=str(os.getgid()),MQTT_PUBLIC_HOST=host,MQTT_PUBLIC_PORT='18883')
(root/'.env').write_text(''.join(k+'='+v+'\n' for k,v in env.items()))
# mosquitto_ctrl creates the plugin's correctly salted credential format.
run('docker','run','--rm','--user',f'{os.getuid()}:{os.getgid()}','-v',str(private)+':/private','--entrypoint','mosquitto_ctrl','eclipse-mosquitto:2.0.22','dynsec','init','/private/dynamic-security.json','admin',password)
# API container uses node uid 1000; use root only for container key access, not host permissions.
print('Local keys and .env created. Start: docker compose --env-file deployment/.env -f deployment/compose.yaml up --build -d')
