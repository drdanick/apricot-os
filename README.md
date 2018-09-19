Apricot OS
==========

A simple proof-of-concept operating system which targets the Apricos CPU architecture.


Description
-----------

Apricot OS is a simple (currently work-in-progress) Operating System which aims to validate the
Apricos architecture as viable for writing non-trivial software.

The following notable features are currently implemented:

- A two stage bootloader
- A collection of system libraries and routines
- A functional shell for user input


Additionally, the following features are planned:

- A functional filesystem
- The ability to execute programs stored on a filesystem
- A simple BASIC interpreter (this is a huge stretch and probably won't happen)

This is definitely by no means intended to be a highly functional Operating System. Instead, this is intended
to provide both a challenge to myself, and to test my patience in developing on such a hugely restrictive platform.


Requirements
------------

In order to assemble Apricot OS, you will need:

- [Apricosasm V1.31+](http://apricot.drdanick.com/apricosasm.jar)

In order to execute the OS, you will need:

- [Apricosim V0.9+](https://github.com/drdanick/apricosim-curses/releases)

Optionally, to see terminal output, you will need:

- [Apricosterm V0.2+](https://github.com/drdanick/apricosterm/releases)

Aside from the assembler, these tools will all need to be built from source. See the relevant project's README
for more information on compile/install procedures.


Assembling
----------

In order to assemble the Operating System, a script has been provided in the project's root directory to automate
most of the process. In order for this script to work, the latest [Apricosasm](https://github.com/drdanick/apricosasm-java/releases)
jar needs to be placed alongside the script. After running the script, the assembled Operating System will be placed in the newly
created `build/` directory.

The assembled Operating System consists of four files, these are:

- **boot.bin**    The assembled first stage bootloader.
- **0.dsk**       The assembled Operating System packaged as an Apricos disk image
- **boot.sym**    The symbols table for the Stage 1 bootloader (used for debugging the bootloader)
- **symbols.sym** The symbols table for the Operating System (used for debugging the OS)


Loading the Bootloader
----------------------

Assuming the Apricos Simulator is installed, all that is needed is to enter `aprsim boot.bin` into your
shell to load the bootlader into the simulator. This will not produce any terminal output, however.
In order to see terminal output, both the simulator and Apricosterm must be started and pointed to the
same FIFO pipe.

For example, open up two terminals and enter _one_ of the following commands into each:

`aprsim -f /tmp/apricosfifo boot.bin` and  
`apricosterm -f /tmp/apricosfifo`

If you would like to load the symbols table and have it display in the simulator, add `-s symbols.sym` to
the aprsim command:

`aprsim -f /tmp/apricosfifo -s symbols.sym boot.bin`

**NOTE:** Since all input is processed by the simulator, mouse focus must be given _always_ to the simulator window,
never the terminal window.


Booting
-------

After loading the bootloader, all that is required to boot is that the simulator be set in 'R' Mode (achieved by
pressing 'm' twice after startup), then pressing 'space'. If all is well, the terminal should start showing output.

**NOTE:** 0.dsk _must_ be present in the current working directory. The first stage bootloader will load this
while booting.


Writing programs
----------------

A sample, non-system program is included in `testprogram.asm`. Since there is currently no mechanism of loading
new programs from a filesystem post-boot, any extra programs must be assembled along with the Operating System
and placed somewhere in memory. In the case of the included test program, it is placed at address 0x1500.

A shell command is included to jump to and execute arbitrary addresses given in hex. To execute the included sample
program, you can enter `memexec 1500` into the shell.

Please see [testprogram.asm](src/testprogram.asm) for more details.


Shell commands
--------------

The Apricot OS shell features a few working commands:

| Command   | Function                                              | Example      |
| --------- | ----------------------------------------------------- | ------------ |
| echo      | Takes a string and echoes it back to the shell        | echo hello   |
| cls       | Clears the screen                                     | cls          |
| memexec   | Jumps to and executes a given 4 character hex address | memexec 1500 |


License
-------

See LICENSE for details.
