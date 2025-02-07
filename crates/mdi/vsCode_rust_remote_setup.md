
## vsCode rust-analyzer remote setup

The following describes how to use vsCode remotely for Rust development.
Instructions are generally specific to the UM Great Lakes server but
can be easily adapted to your server as needed.

### Install the rust-analyzer extension

Install the rust-analyzer extension in vsCode, the one published by rust-lang.org.

### Install or load rust

If you have control over the server and can install rust, do that
as described here:

https://www.rust-lang.org/tools/install

Specifically:

```sh
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

However, if you are working on Great Lakes or another shared
server where you can't install but must load Rust, you need
to create a script that will load Rust as rust-analyzer starts.
Do that as follows:

In vsCode settings.json add the following (change paths to match your home):

```
{
    "rust-analyzer.server.path": "/home/wilsonte/rust-setup.sh",
}
```

Create script `/home/wilsonte/rust-setup.sh` as follows (change paths to match your home):

```sh
#!/bin/bash
module load rust
RUST_ANALYZER=`echo "/home/wilsonte/.vscode-server/extensions/rust-lang.rust-analyzer-*-linux-x64/server/rust-analyzer"`
exec $RUST_ANALYZER "$@"
```

Restart vsCode.

### Help rust-analyzer finds your project/package/crate

To work properly rust-analyzer must be able to find the root of your crate.
It isn't very smart on how to do this. By default it only looks in the
root path of your vsCode workspace for a ```Cargo.toml` file. So,
the simplest way is to open a workspace to the root path of your crate.

Otherwise, you can explicitly enumerate your project using relative
paths to the workspace root by adding the following to settings.json:

```sh
{
    "rust-analyzer.linkedProjects": [
        
    ],
}

However, this isn't great mainly because still have to have a 
single specific workspace root or they will fail anyway.
