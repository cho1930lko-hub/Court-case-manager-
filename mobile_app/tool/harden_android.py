#!/usr/bin/env python3
"""Harden generated Android project: disable Android cloud/device backup."""
import re
import sys
from pathlib import Path

ANDROID = Path("android")
MANIFEST = ANDROID / "app/src/main/AndroidManifest.xml"
RULES = """<?xml version="1.0" encoding="utf-8"?>
<data-extraction-rules>
    <cloud-backup>
        <exclude domain="root" path="." />
        <exclude domain="file" path="." />
        <exclude domain="database" path="." />
        <exclude domain="sharedpref" path="." />
        <exclude domain="external" path="." />
    </cloud-backup>
    <device-transfer>
        <exclude domain="root" path="." />
        <exclude domain="file" path="." />
        <exclude domain="database" path="." />
        <exclude domain="sharedpref" path="." />
        <exclude domain="external" path="." />
    </device-transfer>
</data-extraction-rules>
"""
ACTIVITY_BODY = """
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity()
"""

def fail(message):
    sys.exit(f"harden_android: {message}")

def patch_manifest():
    if not MANIFEST.exists():
        fail(f"{MANIFEST} not found")
    source = MANIFEST.read_text(encoding="utf-8")
    if not re.search(r"<application\b", source):
        fail("no <application> element in AndroidManifest.xml")
    for attr in ("allowBackup", "fullBackupContent", "dataExtractionRules"):
        source = re.sub(rf'\s+android:{attr}="[^"]*"', "", source)
    attrs = ('\n        android:allowBackup="false"'
             '\n        android:fullBackupContent="false"'
             '\n        android:dataExtractionRules="@xml/data_extraction_rules"')
    source = re.sub(r"<application\b", "<application" + attrs, source, count=1)
    MANIFEST.write_text(source, encoding="utf-8")
    xml_dir = ANDROID / "app/src/main/res/xml"
    xml_dir.mkdir(parents=True, exist_ok=True)
    (xml_dir / "data_extraction_rules.xml").write_text(RULES, encoding="utf-8")

def patch_activity():
    found = list((ANDROID / "app/src/main").rglob("MainActivity.kt"))
    if not found:
        fail("MainActivity.kt not found; Kotlin template required")
    path = found[0]
    source = path.read_text(encoding="utf-8")
    if "FLAG_SECURE" not in source and "WindowManager" not in source:
        return
    package = next((line for line in source.splitlines() if line.strip().startswith("package ")), None)
    if package is None:
        fail("package declaration missing")
    path.write_text(package + "\n" + ACTIVITY_BODY, encoding="utf-8")

if __name__ == "__main__":
    patch_manifest()
    patch_activity()
