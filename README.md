# BatteryCap

## 运行（开发）
```bash
swift run
```

## 生成可授权写入的 .app（需要签名）
```bash
scripts/package-app.sh
```

如果需要签名：
```bash
CODESIGN_IDENTITY="你的证书名" scripts/package-app.sh
```

生成的应用位于：`dist/BatteryCap.app`
