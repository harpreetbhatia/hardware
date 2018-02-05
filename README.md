This is a (partial) snapshot of our Verilog verification and extraction development, for the ITP'18 paper Proof-producing extraction to Verilog in HOL.

The development requires [HOL4](https://hol-theorem-prover.org) and [L3](http://www.cl.cam.ac.uk/~acjf3/l3). Make sure to install HOL4 from Git. Try `master` first, and it that does not work try commit `8d28b9b85d195e3015b0a050b177021a86263f39`.

After L3 has been installed, the following commands in the L3 REPL (named `l3`, located in the `bin` directory in your L3 directory) will produce the HOL code for the processor case study:

```
HolExport.spec ("tiny.spec", "tiny");
HolExport.spec ("tinyImpl.spec", "tinyImpl");
```

The file `tinyImpl.spec` describes the processor, and `tiny.spec` is a high-level specification that is not relevant here but is used in `tinyTestProgramsScript.sml` to encode assembly programs. L3 is not essential for using the extraction algorithm, but a convenient way to express low-level HOL4 programs.

The development can then be compiled by a simple `Holmake` call.

The file `verilogScript.sml` specifies the syntax and semantics of Verilog. For example, `exp` is the data type for expressions and `vprog` the data type for statements/processes. The semantics of expressions are given by `erun`, and of statements by `prun`. The `mstep_commit` function gives the semantics of modules (collections of processes).

The extraction algorithm is referred to as "translator" in the development, and can be find in files with "translator" in their name. The file `translatorLib.sml` in particular is interesting, because there one will find the important function `hol2hardware_body`, which is the main entry-point to the extraction algorithm's first phase.

As for the second phase, `tinyMachineScript.sml` defines the next state function for the whole processor case study. But the main file of interest for this phase is `tinyTranslateLib.sml`, which shows how to use the extraction algorithm by extracting the case study processor. There are three calls to the function `hol2hardware_step_function` which translates the processor, memory and accelerator separately. The theorem `computer_Next_relM` illustrates how to use the "large theorem" from the paper to extract a specific program, in this case the processor (and its supporting processes). (Notice the simple and easy to understand theorem statement, compared to the large theorem from the paper.) Below the extraction code there is a call to the pretty-print machinery which produces a `processor.sv` file that can be used for Verilog simulation and synthesis.

The file `tinyTestProgramsScript.sml` includes two small example programs that we have tested on our FPGA board.

As for the two array limitations/hacks mentioned in the paper: The Verilog standard says (more or less) that arrays of different lengths involved in the same operation should be (implicitly) extended to the same length, and operations (including length extensions) should only carry out signed semantics if all expressions involved are signed. In the current version of our semantics this is not formalized, and this is a genuine limitation of our semantics.

The signedness problem is handled by keeping all values unsigned in the semantics, and when signed operations are needed `$signed` casts are added outside the semantics, when pretty-printing, and those casts are in turn wrapped in `$unsigned` casts, as to not "leak". This should be sound for simple expressions at least, but is ugly. (The proper way to solve this is to add the notion of signedness to the semantics.)

The resizing problem is solved less convincingly. In our semantics there is a notion of explicit resizing, which do not have a good correspondence in Verilog. When doing pretty-printing, these explicit resize operations are simply discarded, and we rely on Verilog's implicit resizing semantics to do the correct thing. There might be better hacks for this, but we have not spent any time on looking for such hacks, because our plan is to solve it properly. (The proper way to solve it would be to add the implicit resizing rules to the semantics, and extend the extraction algorithm with a third phase that removes our explicit resizing calls and proves that the implicit resizing semantics provides the same resizing behavior.)

One could have maybe left out these "hacks" and instead said that the extraction algorithm does not handle these cases (i.e., e.g. programs with signed arithmetic are not extractable). How this is framed exactly is not important, but what is important is to somehow mention these limitations, we think, partly because these operations are common, and partly because Verilog's implicit resize semantics and the semantics around signedness are somewhat idiosyncratic (so these issues might hide complications one does not meet when working with more standard (software-like) semantics).

Lastly, as what you see here is just a development snapshot, some future things not included in the paper are included in the files here, and some of the new development contains cheats. Specifically, the cheat in `tinyTranslateLib.sml` is for future processor verification (how to handle writing outside the memory), the cheats in `translatorLib.sml` are for handling slice writes to arrays (which are needed for modeling more complex memories with byte-write support), and the cheats in `translatorScript.sml` concerns translating shift operations.
