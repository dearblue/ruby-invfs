# invfs - customization "require" in VFS support

ruby の ``require`` に仮想ファイルシステム (VFS; Virtual Filesystem) 対応機能を追加します。

  * package name: [invfs](https://github.com/dearblue/ruby-invfs)
  * version: 0.3.1
  * production quality: CONCEPT, EXPERIMENTAL, UNSTABLE
  * license: [BSD-2-clause License](https://github.com/dearblue/ruby-invfs/blob/0.3.1/LICENSE)
  * author: dearblue (<mailto:dearblue@users.noreply.github.com>)
  * report issue to: <https://github.com/dearblue/ruby-invfs/issues>
  * dependency ruby: ruby-2.2+
  * dependency ruby gems:
      * rubyzip-1.2.0 (BSD-2-Clause)
          * https://github.com/rubyzip/rubyzip
          * https://rubygems.org/gems/rubyzip
  * dependency library: (none)
  * bundled external C library: (none)


## How to install (インストールの仕方)

```shell
# gem install invfs
```


## How to use (使い方)

この例では ``mybox.zip`` という Zip 書庫ファイルの中に ``mybox/core.rb``
という Ruby スクリプトファイルが存在しているものとして解説を進めていきます。

mybox.zip の中身:

```text
$ unzip -v mybox.zip
Archive:  mybox.zip
 Length   Method    Size  Cmpr    Date    Time   CRC-32   Name
--------  ------  ------- ---- ---------- ----- --------  ----
      69  Defl:X       60  13% 01-26-2017 00:24 8d7bd341  mybox/core.rb
--------          -------  ---                            -------
      69               60  13%                            1 file
```

mybox/core.rb の中身:

```text
$ unzip -p mybox.zip mybox/core.rb
module MyBox
  def MyBox.sayhello!
    puts "Hello, Ruby!"
  end
end
```

Ruby スクリプトで実際に利用する場合は次のようにします:

```ruby:ruby
require "invfs/zip"           # (1)

$: << InVFS.zip("mybox.zip")  # (2)

require "mybox/core"          # (3)

MyBox.sayhello!
# => Hello, Ruby!
```

 1. ``require "invfs"`` すると、それ以降で VFS を探す機能が利用できるようになります。

    ``require "invfs/zip"`` すると、rubyzip を用いて zip 書庫ファイルから読み込めるようになります。

 2. ``$:`` に VFS としての機能を持った任意のオブジェクトを追加します。

    ``$: << InVFS.zip("mybox.zip")`` の部分です。

 3. ``require`` で任意のライブラリを指定します。

    VFS 内から同じ VFS のファイルを指定したい場合、``require_relative`` も利用できます。


## VFS オブジェクトについて

VFS オブジェクトは ``$:`` に追加する、利用者定義のロードパスと見せかけるオブジェクトです。

このオブジェクトは、以下のメソッドが要求されます。

  * ``.to_path() -> string``
  * ``.file?(path) -> true or false``
  * ``.size(path) -> integer``
  * ``.read(path) -> string as binary``

実際にどのように定義すればいいのかについては、[InVFS::Zip](lib/invfs/zip.rb) あるいは [InVFS::UnionFS](lib/invfs/union.rb)、[InVFS::StringMapFS](lib/invfs/stringmap.rb) を参考にして下さい。

### ``.to_path() -> string``

ロードパスに変換するためのメソッドです。

***文字列を返してください。***

ruby が提供する本来の require の内部や File.join が ``to_path`` して、
文字列以外を文字列に変換するために呼びます
(``file.c:rb_get_path_check_to_string``)。

### ``.file?(path) -> true or false``

VFS 内部にファイルが存在するかを確認するためのメソッドです。

***真偽値を返して下さい。***

path に関して発生した例外は出来る限り捕捉して、false を返すべきです。

### ``.size(path) -> integer``

ファイルサイズを取得するためのメソッドです。

***0 以上の整数値を返して下さい。***

### ``.read(path) -> string as binary``

VFS からファイルを読み込むためのメソッドです。

***文字列、または nil を返して下さい。***


## VFS ハンドラ

``$:`` にファイルを追加した場合、``require`` 時に VFS と解釈可能であれば、内部的にそのファイルを VFS として扱われる機能です。

前にあった例を書き換えた場合の利用例を示します。(2) の部分です。

```ruby
require "invfs/zip"   # (1)

$: << "mybox.zip"     # (2)

require "mybox/core"  # (3)

MyBox.sayhello!
```

VFS ハンドラを利用したい場合は、``.probe`` と ``.open`` メソッドを持ったオブジェクトを ``InVFS.regist`` で登録して下さい。

```ruby
class VFSHandler
  def VFSHandler.probe(file)
    # check available as VFS
  end

  def VFSHandler.open(file)
    # open as VFS
  end

  InVFS.regist self
end
```

実際にどのようにつかっているのかについては、[InVFS::Zip](lib/invfs/zip.rb) を見て下さい。


## Environment Variables (環境変数について)

  * ``RUBY_REQUIRE_INVFS_MAX_LOADSIZE`` :: 読み込みファイルの最大ファイルサイズの指定

    VFS 内における読み込み対象ファイルの最大ファイルサイズを指定することが出来ます。

    数値に続けて接頭辞を付けることが出来ます。以下は 64 MiB とした時の指定です。

    ```shell
    $ export RUBY_REQUIRE_INVFS_MAX_LOADSIZE=64mib
    ```

    最小値は 256 KiB、最大値は 64 MiB、既定値は 2 MiB となっています。


## 課題

  * セキュリティレベル? なにそれおいしいの?

  * マルチスレッド? なにそれおいしいの?

    複数のスレッドで VFS 内のファイルを指定した場合は、``$LOADED_FEATURES``
    に不整合が起きる可能性がある。

  * ``require`` / ``require_relative`` の探索速度がとても遅い。

    ``require "invfs"`` しただけで、3倍以上遅くなる。

    VFS 内の ``.so`` ファイルの読み込みにいたっては、10倍以上遅くなる。

  * VFS オブジェクトのシグネチャが変動すると不整合が起きる。

    ``$LOAD_PATH`` に追加された VFS オブジェクトのシグネチャ (``.to_path``)
    が変動すると、同じライブラリを ``require`` した時に ``$LOADED_FEATURES``
    と一致しなくなるため、再読み込みしてしまう。

    シグネチャの解決に ``.object_id`` などを用いるべき?

    => ``require_relative`` したファイルの VFS が決定しやすくなるが、ファイルパス名
    (VFS 名) が暗号みたくなって特定しづらそう。

  * ``require`` した後に ``$LOAD_PATH`` から VFS オブジェクトを除去すると ``require_relative`` で不具合が起きる。

  * パス解決の正確性を向上させるか?

    ライブラリへの指定が相対パスで、シンボリックリンクが絡んでくると不正確になる。

  * ``require`` されたファイルが VFS から取り出されたのかを確認する処理は文字列の比較であるため不正確。

    これは直接 ``require_relative`` する時の VFS を確認する処理に関係してくる。

    ``caller_locations`` で VFS の直接確認が出来るようにするためには ruby の
    C コードに手を入れなきゃなんないし諦める。
