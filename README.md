## 動かし方

1. CPUのリポジトリ(https://github.com/shinrabansyo/cpu)をcloneして、ビルドする
2. CPUリポジトリの`target/`の中身をを本リポジトリの`src/target/`に丸々コピーする
3. Gowin EDAを立ち上げ、新規ファイルを追加した場合は Add Files から追加する
4. Run All で合成して Programmer で書き込む
5. 動く！

## プログラム

`src/test/` ディレクトリにasmファイルを配置する。
以下のコマンドを実行するとメモリの各バンクを初期化するためのhexファイルが生成される。
（森羅万象アセンブラ `sb_asm_cli` のバイナリにpathを通しておく必要がある）

```
make TESTCASE=path/to/file.asm
```

