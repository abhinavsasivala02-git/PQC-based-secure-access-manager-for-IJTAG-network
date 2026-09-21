import re
raw = open("dbg_out.txt", "rb").read()
txt = raw.decode("utf-16") if raw[:2] in (b"\xff\xfe", b"\xfe\xff") else raw.decode("utf-8", "ignore")
addrs = [int(m) for m in re.findall(r"ENCV t=\d+ data=[0-9a-f]+ addr=(\d+)", txt)]
print("lines:", len(addrs))
print("min:", min(addrs), "max:", max(addrs))
print("u0(0-319):", sum(1 for a in addrs if a < 320),
      "u1(320-639):", sum(1 for a in addrs if 320 <= a < 640),
      "u2(640-959):", sum(1 for a in addrs if 640 <= a < 960),
      "v(>=960):", sum(1 for a in addrs if a >= 960))