q = 3329
R = 2285  # 2^16 mod q

def br7(i):
    return int(f"{i:07b}"[::-1], 2)

zetas_mont = [pow(17, br7(i), q) * R % q for i in range(128)]
zetas_signed = [v if v < q // 2 else v - q for v in zetas_mont]

real = """-1044  -758  -359 -1517  1493  1422   287   202
-171   622  1577   182   962 -1202 -1474  1468
573 -1325   264   383  -829  1458 -1602  -130
-681  1017   732   608 -1542   411  -205 -1571
1223   652  -552  1015 -1293  1491  -282 -1544
516    -8  -320  -666 -1618 -1162   126  1469
-853   -90  -271   830   107 -1421  -247  -951
-398   961 -1508  -725   448 -1065   677 -1275
-1103   430   555   843 -1251   871  1550   105
422   587   177  -235  -291  -460  1574  1653
-246   778  1159  -147  -777  1483  -602  1119
-1590   644  -872   349   418   329  -156   -75
817  1097   603   610  1322 -1285 -1465   384
-1215  -136  1218 -1335  -874   220 -1187 -1659
-1185 -1530 -1278   794 -1510  -854  -870   478
-108  -308   996   991   958 -1460  1522  1628""".split()
real = [int(x) for x in real]

assert zetas_signed == real, "computed != real Kyber zetas"
print("computed table matches authoritative zetas[128]")
case_lines = []
for i, v in enumerate(zetas_signed):
    case_lines.append(f"            7'd{i:>3}: zeta_comb = {'-' if v < 0 else ' '}16'sd{abs(v)};")
open("zeta_case.txt", "w").write("\n".join(case_lines))
print("wrote zeta_case.txt")