#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ZTE U60 Pro ADB Debug Enabler
Based on PHP script by NekoYuzu (MlgmXyysd)
Python version for easier use
"""

import requests
import time
import hashlib
import json
import sys

# =====================
#    Config Section
# =====================

# Gateway address (your U60 Pro IP)
Gateway = "192.168.0.1"

# Admin password (CHANGE THIS to your device password!)
Password = "86558781"  # <-- Fill in your password here!

# =====================
#    Functions
# =====================

def post_api(url, data, debug=False):
    """Send JSON-RPC request to device"""
    headers = {"Content-Type": "application/json"}
    try:
        if debug:
            print(f"    [DEBUG] URL: {url}")
            print(f"    [DEBUG] Request: {json.dumps(data, indent=4)}")
        response = requests.post(url, json=data, headers=headers, timeout=10)
        if debug:
            print(f"    [DEBUG] HTTP Status: {response.status_code}")
            print(f"    [DEBUG] Response Headers: {dict(response.headers)}")
            print(f"    [DEBUG] Response Text: {response.text[:500]}")
        return response.json()
    except Exception as e:
        if debug:
            print(f"    [DEBUG] Exception: {e}")
        return {"error": str(e)}

def get_timestamp():
    """Get current timestamp in milliseconds"""
    return int(time.time() * 1000)

def main():
    global Gateway, Password

    # Check if password is set
    if not Password:
        print("Error: Please set your admin password in the script!")
        print("Edit the 'Password' variable at line 20")
        sys.exit(1)

    print(f"[*] Target: http://{Gateway}")
    print(f"[*] Step 1: Fetching login salt...")

    # Step 1: Get salt
    url = f"http://{Gateway}/ubus/?t={get_timestamp()}"
    salt_data = [{
        "jsonrpc": "2.0",
        "id": 1,
        "method": "call",
        "params": [
            "00000000000000000000000000000000",
            "zwrt_web",
            "web_login_info",
            {"": ""}
        ]
    }]

    result = post_api(url, salt_data, debug=True)

    if not result or "error" in result[0] if result else True:
        print(f"[!] Failed to fetch salt")
        print(f"    Response: {result}")
        sys.exit(1)

    try:
        salt = result[0]["result"][1]["zte_web_sault"]
        print(f"[+] Got salt: {salt}")
    except (KeyError, IndexError, TypeError) as e:
        print(f"[!] Failed to parse salt from response")
        print(f"    Response: {result}")
        sys.exit(1)

    # Step 2: Hash password with salt
    print(f"[*] Step 2: Hashing password...")
    hash1 = hashlib.sha256(Password.encode()).hexdigest().upper()
    hash2 = hashlib.sha256((hash1 + salt).encode()).hexdigest().upper()
    print(f"[+] Password hash: {hash2}")

    # Step 3: Login
    print(f"[*] Step 3: Logging in...")
    url = f"http://{Gateway}/ubus/?t={get_timestamp()}"
    login_data = [{
        "jsonrpc": "2.0",
        "id": 2,
        "method": "call",
        "params": [
            "00000000000000000000000000000000",
            "zwrt_web",
            "web_login",
            {"password": hash2}
        ]
    }]

    result = post_api(url, login_data, debug=True)

    if not result or "error" in result[0] if result else True:
        print(f"[!] Login failed - check your password!")
        print(f"    Response: {result}")
        sys.exit(1)

    try:
        session = result[0]["result"][1]["ubus_rpc_session"]
        print(f"[+] Session: {session}")
    except (KeyError, IndexError, TypeError) as e:
        print(f"[!] Failed to get session")
        print(f"    Response: {result}")
        sys.exit(1)

    # Step 4: Enable USB debug mode
    print(f"[*] Step 4: Enabling USB debug mode...")
    url = f"http://{Gateway}/ubus/?t={get_timestamp()}"
    debug_data = [{
        "jsonrpc": "2.0",
        "id": 3,
        "method": "call",
        "params": [
            session,
            "zwrt_bsp.usb",
            "set",
            {"mode": "debug"}
        ]
    }]

    result = post_api(url, debug_data, debug=True)
    print(f"[*] Response: {json.dumps(result, indent=2)}")

    # Step 5: Try different ways to check USB status
    print(f"\n[*] Step 5: Checking USB debug status...")

    # Try method 1: zwrt_bsp.usb get
    url = f"http://{Gateway}/ubus/?t={get_timestamp()}"
    status_data = [{
        "jsonrpc": "2.0",
        "id": 4,
        "method": "call",
        "params": [
            session,
            "zwrt_bsp.usb",
            "get",
            {}
        ]
    }]
    status_result = post_api(url, status_data, debug=True)
    print(f"[*] USB Status (zwrt_bsp.usb get): {json.dumps(status_result, indent=2)}")

    # Try method 2: zwrt_bsp.usb status
    url = f"http://{Gateway}/ubus/?t={get_timestamp()}"
    status_data2 = [{
        "jsonrpc": "2.0",
        "id": 5,
        "method": "call",
        "params": [
            session,
            "zwrt_bsp.usb",
            "status",
            {}
        ]
    }]
    status_result2 = post_api(url, status_data2, debug=True)
    print(f"[*] USB Status (zwrt_bsp.usb status): {json.dumps(status_result2, indent=2)}")

    # Try method 3: zwrt_bsp get_usb
    url = f"http://{Gateway}/ubus/?t={get_timestamp()}"
    status_data3 = [{
        "jsonrpc": "2.0",
        "id": 6,
        "method": "call",
        "params": [
            session,
            "zwrt_bsp",
            "get_usb",
            {}
        ]
    }]
    status_result3 = post_api(url, status_data3, debug=True)
    print(f"[*] USB Status (zwrt_bsp get_usb): {json.dumps(status_result3, indent=2)}")

    # Try method 4: zwrt_bsp.usb list
    url = f"http://{Gateway}/ubus/?t={get_timestamp()}"
    status_data4 = [{
        "jsonrpc": "2.0",
        "id": 7,
        "method": "call",
        "params": [
            session,
            "zwrt_bsp.usb",
            "list",
            {}
        ]
    }]
    status_result4 = post_api(url, status_data4, debug=True)
    print(f"[*] USB Status (zwrt_bsp.usb list): {json.dumps(status_result4, indent=2)}")

    # Try method 5: file.exec - check if adb exists
    print(f"\n[*] Step 6: Checking if ADB service exists...")
    url = f"http://{Gateway}/ubus/?t={get_timestamp()}"
    adb_check = [{
        "jsonrpc": "2.0",
        "id": 8,
        "method": "call",
        "params": [
            session,
            "file",
            "exec",
            {"command": "ls", "params": ["/system/bin/adb*"]}
        ]
    }]
    adb_result = post_api(url, adb_check, debug=True)
    print(f"[*] ADB check: {json.dumps(adb_result, indent=2)}")

    # Try method 6: service list
    url = f"http://{Gateway}/ubus/?t={get_timestamp()}"
    service_list = [{
        "jsonrpc": "2.0",
        "id": 9,
        "method": "call",
        "params": [
            session,
            "service",
            "list",
            {"name": "adbd"}
        ]
    }]
    service_result = post_api(url, service_list, debug=True)
    print(f"[*] Service list (adbd): {json.dumps(service_result, indent=2)}")

    # Check result
    debug_success = result and result[0].get("result") == [0]

    # Analyze all status results
    print()
    print("=" * 50)
    print("[*] ANALYSIS")
    print("=" * 50)

    if debug_success:
        print("[+] Step 4: API call returned success (result=[0])")
    else:
        print("[!] Step 4: API call failed")

    # Check if any status query returned useful info
    all_results = [status_result, status_result2, status_result3, status_result4]
    found_mode = False
    for i, res in enumerate(all_results, 1):
        if res and len(res) > 0:
            r = res[0].get("result", [])
            if isinstance(r, list) and len(r) > 1 and isinstance(r[1], dict):
                print(f"[+] Status method {i} returned data: {r[1]}")
                found_mode = True

    if not found_mode:
        print("[!] All status queries returned error codes (not data)")
        print("[!] This suggests the API may not support status queries")
        print("[!] OR the session lacks permission")

    print()
    print("=" * 50)
    print("[*] IMPORTANT: Device screen message detected")
    print("=" * 50)
    print()
    print("The device shows: '你已经登陆WebUI，请解锁屏幕后再使用屏幕操作'")
    print("This means:")
    print("  1. The device DETECTED the API call")
    print("  2. But the screen is LOCKED")
    print("  3. Screen operations are BLOCKED until unlocked")
    print()
    print("SOLUTION:")
    print("  1. UNLOCK the device screen FIRST")
    print("  2. Then run this script again")
    print("  3. Connect via USB and run: adb devices")
    print()
    print("Alternative: Try using ADB over WiFi if supported:")
    print(f"  adb connect {Gateway}:5555")
    print()

if __name__ == "__main__":
    main()
