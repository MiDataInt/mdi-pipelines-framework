## vsCode rust-analyzer remote setup

The following describes how to use vsCode remotely for Rust development.
Some instructions below are specific to the UM Great Lakes server but
can be easily adapted to your server as needed.

Be patient if it takes you a few minutes to get it set up, it is worth 
it as the rust-analyzer is an amazingly powerful code development tool.

### Install the rust-analyzer extension

Install the `rust-analyzer` extension in vsCode, the one published by 
rust-lang.org. Do this while connected remotely to ensure that 
rust-analyzer is installed on the remote host.

### Install or load rust

If the Rust language compiler [cargo](https://doc.rust-lang.org/cargo/)
is already available on your server, you're good to go.

Otherwise, if you have control over the server and can install rust, 
do that as described here in https://www.rust-lang.org/tools/install.
Specifically:

```sh
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

However, if you are working on Great Lakes or another shared
server where you can't install but must instead load Rust, you need
to create a script that will load Rust before rust-analyzer starts.
Do that as follows:

Press `Ctrl-Shift-P`, then search for and open `Preferences: Open Remote Settings`.
Edit that settings.json file to add the following 
(throughout, change `<USER>` or the path to match your home directory):

```
{
    "rust-analyzer.server.path": "/home/<USER>/rust-setup.sh",
}
```

Create script `/home/<USER>/rust-setup.sh` as follows:

```sh
#!/bin/bash
module load rust # or whatever command loads rust on your server
RUST_ANALYZER=`echo "/home/<USER>/.vscode-server/extensions/rust-lang.rust-analyzer-*-linux-x64/server/rust-analyzer"`
exec $RUST_ANALYZER "$@"
```

Restart vsCode to force rust-analyzer to reload.

### Help rust-analyzer find your project/package/crate

To work properly, rust-analyzer must be able to find the root of your crate.
It isn't very smart on how to do this. By default it only looks in the
root path of your vsCode workspace for a `Cargo.toml` file. So,
the simplest way is to open a workspace to the root path of your crate,
which is what we normally do.

Otherwise, you can explicitly enumerate your project using relative
paths to the workspace root by adding the following to settings.json:

```sh
{
    "rust-analyzer.linkedProjects": [
        
    ],
}
```

However, this isn't great mainly because you still have to have a 
single specific workspace root or they will fail anyway.
