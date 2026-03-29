const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const os = target.result.os.tag;

    // ---------------------------------------------------------------
    // Phase 1: Bootstrap — build the harbour compiler from pure C
    // ---------------------------------------------------------------

    // Bootstrap libraries are always ReleaseFast — they're linked into the
    // drydock compiler which is used as a build tool for .prg compilation.
    // Debug mode triggers UB sanitizers on legacy C code (separate investigation).
    const boot_opt: std.builtin.OptimizeMode = .ReleaseFast;
    const hbcommon = addCLib(b, "hbcommon", "src/common", common_srcs, target, boot_opt);
    const hbnortl = addCLib(b, "hbnortl", "src/nortl", &.{"nortl.c"}, target, boot_opt);
    const hbpp = addCLib(b, "hbpp", "src/pp", pp_srcs, target, boot_opt);

    // Compiler library — needs pre-generated parser (harbour.yyc/yyh → harboury.c/h)
    const hbcplr = addCLib(b, "hbcplr", "src/compiler", compiler_srcs, target, boot_opt);
    hbcplr.addCSourceFile(.{ .file = b.path("src/compiler/harboury.c"), .flags = harbour_cflags });
    hbcplr.addIncludePath(b.path("src/compiler"));

    // drydock compiler executable — always ReleaseFast because it's used as a
    // build tool for .prg compilation. Debug mode triggers UB sanitizers on
    // legacy C code that needs separate investigation.
    const harbour = b.addExecutable(.{ .name = "drydock", .target = target, .optimize = .ReleaseFast });
    harbour.addCSourceFile(.{ .file = b.path("src/main/harbour.c"), .flags = harbour_cflags });
    harbour.addIncludePath(b.path("include"));
    harbour.linkLibrary(hbcplr);
    harbour.linkLibrary(hbpp);
    harbour.linkLibrary(hbnortl);
    harbour.linkLibrary(hbcommon);
    linkSysLibs(harbour, os, false);
    b.installArtifact(harbour);

    // ---------------------------------------------------------------
    // Phase 2: Runtime — all C libraries (no .prg yet)
    // ---------------------------------------------------------------

    // VM — uses hvmall.c amalgamation for better inlining
    const hbvm = addCLib(b, "hbvm", "src/vm", vm_srcs, target, optimize);

    // VM multi-threaded variant
    const hbvmmt = addCLib(b, "hbvmmt", "src/vm", vm_srcs, target, optimize);
    hbvmmt.defineCMacro("HB_MT_VM", null);

    // Third-party: PCRE
    const hbpcre = addCLib(b, "hbpcre", "src/3rd/pcre", pcre_srcs, target, optimize);
    hbpcre.defineCMacro("PCRE_STATIC", null);
    hbpcre.defineCMacro("SUPPORT_UTF", null);
    hbpcre.defineCMacro("SUPPORT_UCP", null);
    hbpcre.defineCMacro("HAVE_CONFIG_H", null);
    if (os != .windows) hbpcre.defineCMacro("HAVE_STDINT_H", null);

    // Third-party: zlib
    const hbzlib = addCLib(b, "hbzlib", "src/3rd/zlib", zlib_srcs, target, optimize);
    if (os != .windows) hbzlib.defineCMacro("HAVE_UNISTD_H", null);

    // RTL — the largest library
    const hbrtl = addCLib(b, "hbrtl", "src/rtl", rtl_srcs, target, optimize);
    hbrtl.defineCMacro("HB_HAS_PCRE", null);
    hbrtl.defineCMacro("PCRE_STATIC", null);
    hbrtl.defineCMacro("HB_HAS_ZLIB", null);
    hbrtl.addIncludePath(b.path("src/3rd/pcre"));
    hbrtl.addIncludePath(b.path("src/3rd/zlib"));

    // Macro compiler — needs pre-generated parser (macro.yyc/yyh → macroy.c/h)
    const hbmacro = addCLib(b, "hbmacro", "src/macro", macro_srcs, target, optimize);
    hbmacro.addCSourceFile(.{ .file = b.path("src/macro/macroy.c"), .flags = harbour_cflags });
    hbmacro.addIncludePath(b.path("src/macro"));

    // RDD — base + drivers
    const hbrdd = addCLib(b, "hbrdd", "src/rdd", rdd_srcs, target, optimize);
    const rddntx = addCLib(b, "rddntx", "src/rdd/dbfntx", &.{"dbfntx1.c"}, target, optimize);
    const rddcdx = addCLib(b, "rddcdx", "src/rdd/dbfcdx", &.{ "dbfcdx1.c", "sixcdx1.c" }, target, optimize);
    const rddfpt = addCLib(b, "rddfpt", "src/rdd/dbffpt", &.{"dbffpt1.c"}, target, optimize);
    const rddnsx = addCLib(b, "rddnsx", "src/rdd/dbfnsx", &.{"dbfnsx1.c"}, target, optimize);
    const hbsix = addCLib(b, "hbsix", "src/rdd/hbsix", hbsix_srcs, target, optimize);
    const hbhsx = addCLib(b, "hbhsx", "src/rdd/hsx", &.{ "cftsfunc.c", "hsx.c" }, target, optimize);
    const hbusrrdd = addCLib(b, "hbusrrdd", "src/rdd/usrrdd", &.{"usrrdd.c"}, target, optimize);
    const hbnulrdd = addCLib(b, "hbnulrdd", "src/rdd/nulsys", &.{"nulsys.c"}, target, optimize);

    // Codepage, language, debug
    const hbcpage = addCLib(b, "hbcpage", "src/codepage", codepage_srcs, target, optimize);
    const hblang = addCLib(b, "hblang", "src/lang", lang_srcs, target, optimize);
    const hbdebug = addCLib(b, "hbdebug", "src/debug", &.{"dbgentry.c"}, target, optimize);

    // GT drivers — always built
    const gtstd = addCLib(b, "gtstd", "src/rtl/gtstd", &.{"gtstd.c"}, target, optimize);
    const gtcgi = addCLib(b, "gtcgi", "src/rtl/gtcgi", &.{"gtcgi.c"}, target, optimize);
    const gtpca = addCLib(b, "gtpca", "src/rtl/gtpca", &.{"gtpca.c"}, target, optimize);

    // GT drivers — platform-conditional
    if (os == .linux or os == .freebsd or os == .openbsd or os == .netbsd) {
        b.installArtifact(addCLib(b, "gttrm", "src/rtl/gttrm", &.{"gttrm.c"}, target, optimize));
    }
    if (os == .windows) {
        b.installArtifact(addCLib(b, "gtwin", "src/rtl/gtwin", &.{"gtwin.c"}, target, optimize));
        b.installArtifact(addCLib(b, "gtwvt", "src/rtl/gtwvt", &.{"gtwvt.c"}, target, optimize));
        b.installArtifact(addCLib(b, "gtgui", "src/rtl/gtgui", &.{"gtgui.c"}, target, optimize));
    }

    // ---------------------------------------------------------------
    // Phase 3: Compile .prg → .c → .o (release mode)
    // Uses bin/prg2c.sh to run the drydock compiler on each .prg file,
    // capturing the generated C via stdout.
    // ---------------------------------------------------------------

    // VM: harbinit.prg
    addPrgSources(b, harbour, hbvm, "src/vm", &.{"harbinit.prg"});

    // RTL: 74 .prg files
    addPrgSources(b, harbour, hbrtl, "src/rtl", rtl_prg_srcs);

    // RDD: 12 .prg files
    addPrgSources(b, harbour, hbrdd, "src/rdd", rdd_prg_srcs);

    // hbsix: 3 .prg files
    addPrgSources(b, harbour, hbsix, "src/rdd/hbsix", &.{ "sxcompat.prg", "sxini.prg", "sxtrig.prg" });

    // Debug: 13 .prg files
    addPrgSources(b, harbour, hbdebug, "src/debug", debug_prg_srcs);

    // hbextern: 1 .prg file
    const hbextern = addCLib(b, "hbextern", "src/hbextern", &.{}, target, optimize);
    addPrgSources(b, harbour, hbextern, "src/hbextern", &.{"hbextern.prg"});

    // ---------------------------------------------------------------
    // Phase 4: Executables
    // ---------------------------------------------------------------

    // ddtest — test suite executable
    // Note: gtsys.c was removed from hbrtl to avoid duplicate symbol conflicts
    // with .prg-generated REQUEST stubs. GT drivers are linked separately.
    const runtime_libs = &[_]*std.Build.Step.Compile{
        hbvm, hbrtl, hbmacro, hbrdd, rddntx, rddcdx, rddfpt, rddnsx,
        hbsix, hbhsx, hbusrrdd, hbnulrdd, hbcpage, hblang, hbdebug,
        hbextern, hbpcre, hbzlib, hbcommon, gtstd, gtcgi,
    };
    const ddtest = addPrgExe(b, harbour, "ddtest", "utils/hbtest", hbtest_prg_srcs, target, optimize, os, runtime_libs);
    // hbtest also has a C source file with helper functions
    ddtest.addCSourceFile(.{ .file = b.path("utils/hbtest/rt_miscc.c"), .flags = harbour_cflags });

    // Install all libraries
    const all_libs = [_]*std.Build.Step.Compile{
        hbcommon, hbnortl, hbpp, hbcplr, hbvm, hbvmmt,
        hbpcre,  hbzlib,  hbrtl, hbmacro, hbrdd,
        rddntx,  rddcdx,  rddfpt, rddnsx, hbsix,
        hbhsx,   hbusrrdd, hbnulrdd,
        hbcpage, hblang,  hbdebug, hbextern,
        gtstd,   gtcgi,   gtpca,
    };
    for (&all_libs) |lib| {
        b.installArtifact(lib);
    }

    // ---------------------------------------------------------------
    // Steps
    // ---------------------------------------------------------------

    const run_step = b.step("run", "Run the drydock compiler");
    const run_cmd = b.addRunArtifact(harbour);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    run_step.dependOn(&run_cmd.step);

    // Test step
    const test_step = b.step("test", "Run ddtest");
    const test_cmd = b.addRunArtifact(ddtest);
    test_step.dependOn(&test_cmd.step);
}

// ---------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------

fn addCLib(
    b: *std.Build,
    name: []const u8,
    root: []const u8,
    srcs: []const []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const lib = b.addStaticLibrary(.{
        .name = name,
        .target = target,
        .optimize = optimize,
    });
    lib.addCSourceFiles(.{
        .root = b.path(root),
        .files = srcs,
        .flags = harbour_cflags,
    });
    lib.addIncludePath(b.path("include"));
    lib.linkLibC();
    return lib;
}

/// Compile .prg files to .c and add to a library.
fn addPrgSources(
    b: *std.Build,
    compiler: *std.Build.Step.Compile,
    lib: *std.Build.Step.Compile,
    prg_root: []const u8,
    prg_files: []const []const u8,
) void {
    for (prg_files) |prg_file| {
        lib.addCSourceFile(.{
            .file = compilePrg(b, compiler, prg_root, prg_file),
            // captureStdOut() produces a file named "stdout" with no extension.
            // -x c tells the C compiler to treat it as C source regardless.
            .flags = prg_cflags,
        });
    }
}

/// Run drydock on a .prg file and return the generated .c as a LazyPath.
/// Uses a shell one-liner to compile .prg → .c via a temp directory,
/// then copies the result to a zig-managed output file with .c extension.
fn compilePrg(
    b: *std.Build,
    compiler: *std.Build.Step.Compile,
    prg_root: []const u8,
    prg_file: []const u8,
) std.Build.LazyPath {
    const c_name = changeExtension(b, prg_file, ".c");

    // bin/prg2c.sh <compiler> <include_dir> <input.prg>
    // Writes generated C to stdout.
    const cmd = b.addSystemCommand(&.{"bin/prg2c.sh"});
    cmd.addArtifactArg(compiler);
    cmd.addDirectoryArg(b.path("include"));
    cmd.addFileArg(b.path(b.fmt("{s}/{s}", .{ prg_root, prg_file })));
    const stdout = cmd.captureStdOut();

    // captureStdOut produces a file named "stdout" with no extension.
    // Copy it to a .c-named file so zig's C compiler recognizes it.
    const rename = b.addSystemCommand(&.{"cp"});
    rename.addFileArg(stdout);
    const output = rename.addOutputFileArg(c_name);
    return output;
}

/// Build an executable from .prg sources linked against runtime libraries.
fn addPrgExe(
    b: *std.Build,
    compiler: *std.Build.Step.Compile,
    name: []const u8,
    prg_root: []const u8,
    prg_files: []const []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    os: std.Target.Os.Tag,
    libs: []const *std.Build.Step.Compile,
) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{ .name = name, .target = target, .optimize = optimize });
    exe.addIncludePath(b.path("include"));
    for (prg_files) |prg_file| {
        exe.addCSourceFile(.{
            .file = compilePrg(b, compiler, prg_root, prg_file),
            .flags = prg_cflags,
        });
    }
    for (libs) |lib| exe.linkLibrary(lib);
    linkSysLibs(exe, os, true);
    b.installArtifact(exe);
    return exe;
}

/// Replace the extension of a filename: "foo.prg" → "foo.c"
/// Uses the build allocator so the result outlives the call.
fn changeExtension(b: *std.Build, filename: []const u8, new_ext: []const u8) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, filename, '.')) |dot| {
        return b.fmt("{s}{s}", .{ filename[0..dot], new_ext });
    }
    return filename;
}

fn linkSysLibs(exe: *std.Build.Step.Compile, os: std.Target.Os.Tag, link_rt: bool) void {
    if (os == .windows) {
        for (&[_][]const u8{ "kernel32", "user32", "gdi32", "winmm", "winspool", "ws2_32" }) |lib| {
            exe.linkSystemLibrary(lib);
        }
    } else {
        exe.linkSystemLibrary("m");
        if (link_rt) {
            exe.linkSystemLibrary("dl");
            exe.linkSystemLibrary("pthread");
            exe.linkSystemLibrary("rt");
        }
    }
    exe.linkLibC();
}

// ---------------------------------------------------------------
// Compiler flags
// ---------------------------------------------------------------

const harbour_cflags: []const []const u8 = &.{
    "-Wall",
    "-W",
    "-O3",
};

// Flags for compiling generated .prg → .c output. The -x c flag is needed
// because captureStdOut() produces a file named "stdout" with no extension,
// and zig's C compiler needs to know it's C source.
const prg_cflags: []const []const u8 = &.{
    "-Wall",
    "-W",
    "-O3",
    "-x",
    "c",
};

// ---------------------------------------------------------------
// Source file lists (from Makefiles — authoritative)
// ---------------------------------------------------------------

const common_srcs: []const []const u8 = &.{
    "expropt1.c", "expropt2.c", "funcid.c",    "hbarch.c",
    "hbdate.c",   "hbffind.c",  "hbfopen.c",   "hbfsapi.c",
    "hbgete.c",   "hbhash.c",   "hbmem.c",     "hbprintf.c",
    "hbstrbm.c",  "hbstr.c",    "hbtrace.c",   "hbver.c",
    "hbverdsp.c", "hbwin.c",    "hbwince.c",   "strwild.c",
};

const pp_srcs: []const []const u8 = &.{
    "pptable.c", "ppcore.c", "pplib.c", "pplib2.c",
};

const compiler_srcs: []const []const u8 = &.{
    "cmdcheck.c", "compi18n.c", "complex.c",  "expropta.c",
    "exproptb.c", "genc.c",     "gencc.c",    "gendis.c",   "genhrb.c",
    "hbcmplib.c", "hbcomp.c",   "hbdbginf.c", "hbdead.c",
    "hbfix.c",    "hbfunchk.c", "hbgenerr.c", "hbident.c",
    "hblbl.c",    "hbmain.c",   "hbopt.c",    "hbpcode.c",
    "hbstripl.c", "hbusage.c",  "ppcomp.c",
};

// VM uses hvmall.c amalgamation + unconditional extra files + main.c (Linux)
const vm_srcs: []const []const u8 = &.{
    "hvmall.c",   "arrayshb.c", "asort.c",    "break.c",
    "cmdarg.c",   "debug.c",    "dynlibhb.c", "eval.c",
    "evalhb.c",   "extrap.c",   "hashfunc.c", "initexit.c",
    "initsymb.c", "memvclip.c", "pbyref.c",   "pcount.c",
    "pvalue.c",   "pvaluehb.c", "proc.c",     "procaddr.c",
    "runner.c",   "short.c",    "vm.c",       "main.c",
};

const macro_srcs: []const []const u8 = &.{
    "macroa.c", "macrob.c", "macrolex.c",
};

const rdd_srcs: []const []const u8 = &.{
    "dbcmd.c",   "dbcmd53.c", "dbcmdhb.c",  "dbdetach.c",
    "dbdrop.c",  "dbexists.c", "dbf1.c",     "dbnubs.c",
    "dbrename.c", "dbsql.c",   "delim1.c",   "fieldhb.c",
    "ordcount.c", "ordwldsk.c", "workarea.c", "wacore.c",
    "wafunc.c",  "rddinfo.c", "rddshort.c", "sdf1.c",
};

const hbsix_srcs: []const []const u8 = &.{
    "sxcompr.c", "sxcrypt.c", "sxdate.c",  "sxfname.c",
    "sxord.c",   "sxredir.c", "sxsem.c",   "sxtable.c",
    "sxutil.c",
};

const pcre_srcs: []const []const u8 = &.{
    "chartabs.c",  "pcrebyte.c", "pcrecomp.c", "pcreconf.c",
    "pcredfa.c",   "pcreexec.c", "pcrefinf.c", "pcreget.c",
    "pcreglob.c",  "pcrejitc.c", "pcremktb.c", "pcrenewl.c",
    "pcreoutf.c",  "pcrerefc.c", "pcrestud.c", "pcretabs.c",
    "pcreucd.c",   "pcrever.c",  "pcrevutf.c", "pcrexcls.c",
};

const zlib_srcs: []const []const u8 = &.{
    "adler32.c", "compress.c", "crc32.c",   "deflate.c",
    "gzclose.c", "gzlib.c",    "gzread.c",  "gzwrite.c",
    "infback.c", "inffast.c",  "inflate.c", "inftrees.c",
    "trees.c",   "uncompr.c",  "zutil.c",
};

const lang_srcs: []const []const u8 = &.{
    "l_be.c",     "l_bg.c",     "l_ca.c",     "l_cs.c",
    "l_de.c",     "l_de_at.c",  "l_ee.c",     "l_el.c",
    "l_eo.c",     "l_es.c",     "l_es_419.c", "l_eu.c",
    "l_fr.c",     "l_gl.c",     "l_he.c",     "l_hr.c",
    "l_hu.c",     "l_id.c",     "l_is.c",     "l_it.c",
    "l_ko.c",     "l_lt.c",     "l_lv.c",     "l_nl.c",
    "l_pl.c",     "l_pt.c",     "l_pt_br.c",  "l_ro.c",
    "l_ru.c",     "l_sk.c",     "l_sl.c",     "l_sr_cyr.c",
    "l_sr_lat.c", "l_sv.c",     "l_tr.c",     "l_uk.c",
    "l_zh.c",     "l_zh_sim.c",
};

const codepage_srcs: []const []const u8 = &.{
    "cp_950.c",   "cp_big5.c",  "cp_gbk.c",   "cp_utf8.c",
    "cp_u16le.c", "cpbg866.c",  "cpbgiso.c",  "cpbgmik.c",
    "cpbgwin.c",  "cpcs852.c",  "cpcs852c.c", "cpcsiso.c",
    "cpcskamc.c", "cpcswin.c",  "cpde850.c",  "cpde850m.c",
    "cpde858.c",  "cpdeiso.c",  "cpdewin.c",  "cpdk865.c",
    "cpee775.c",  "cpeewin.c",  "cpel437.c",  "cpel737.c",
    "cpeliso.c",  "cpelwin.c",  "cpes850.c",  "cpes850c.c",
    "cpes850m.c", "cpesiso.c",  "cpesmwin.c", "cpeswin.c",
    "cpfi850.c",  "cpfr850.c",  "cpfr850c.c", "cpfr850m.c",
    "cpfriso.c",  "cpfrwin.c",  "cphe862.c",  "cphewin.c",
    "cphr646.c",  "cphr852.c",  "cphriso.c",  "cphrwin.c",
    "cphu852.c",  "cphu852c.c", "cphuiso.c",  "cphuwin.c",
    "cpis850.c",  "cpis861.c",  "cpit437.c",  "cpit850.c",
    "cpit850m.c", "cpitisb.c",  "cpitiso.c",  "cpitwin.c",
    "cplt775.c",  "cpltwin.c",  "cplv775.c",  "cplvwin.c",
    "cpnl850.c",  "cpnl850m.c", "cpno865.c",  "cppl852.c",
    "cppliso.c",  "cpplmaz.c",  "cpplwin.c",  "cppt850.c",
    "cppt860.c",  "cpptiso.c",  "cpro852.c",  "cproiso.c",
    "cprowin.c",  "cpru1251.c", "cpru866.c",  "cpruiso.c",
    "cprukoi8.c", "cpsk852.c",  "cpsk852c.c", "cpskiso.c",
    "cpskkamc.c", "cpskwin.c",  "cpsl646.c",  "cpsl852.c",
    "cpsliso.c",  "cpslwin.c",  "cpsr646.c",  "cpsr646c.c",
    "cpsrwin.c",  "cpsv437c.c", "cpsv850.c",  "cpsv850m.c",
    "cpsviso.c",  "cpsvwin.c",  "cptr857.c",  "cptriso.c",
    "cptrwin.c",  "cpua1125.c", "cpua1251.c", "cpua866.c",
    "cpuakoi8.c", "uc1125.c",   "uc1250.c",   "uc1251.c",
    "uc1252.c",   "uc1253.c",   "uc1254.c",   "uc1255.c",
    "uc1256.c",   "uc1257.c",   "uc1258.c",   "uc646_yu.c",
    "uc646yuc.c", "uc737.c",    "uc775.c",    "uc850.c",
    "uc852.c",    "uc855.c",    "uc857.c",    "uc858.c",
    "uc860.c",    "uc861.c",    "uc862.c",    "uc863.c",
    "uc864.c",    "uc865.c",    "uc866.c",    "uc869.c",
    "uc874.c",    "uc8859_1.c", "uc88591b.c", "uc8859_2.c",
    "uc8859_3.c", "uc8859_4.c", "uc8859_5.c", "uc8859_6.c",
    "uc8859_7.c", "uc8859_8.c", "uc8859_9.c", "uc885910.c",
    "uc885911.c", "uc885913.c", "uc885914.c", "uc885915.c",
    "uc885916.c", "uckam.c",    "uckoi8.c",   "uckoi8u.c",
    "ucmaz.c",    "ucmik.c",    "uc037.c",    "uc1006.c",
    "uc1026.c",   "uc424.c",    "uc500.c",    "uc856.c",
    "uc875.c",    "ucascii.c",  "ucatari.c",  "ucmacce.c",
    "ucmaccyr.c", "ucmacgrk.c", "ucmacice.c", "ucmacrom.c",
    "ucmactrk.c", "ucnext.c",
};

// RTL — 217 C source files (from src/rtl/Makefile C_SOURCES)
const rtl_srcs: []const []const u8 = &.{
    "abs.c",       "accept.c",   "ampm.c",      "arc4.c",
    "at.c",        "ati.c",      "base64c.c",   "base64d.c",
    "binnum.c",    "box.c",      "cdpapi.c",    "cdpapihb.c",
    "cdpbox.c",    "cdpdetc.c",  "chrasc.c",    "chruni.c",
    "colorind.c",  "console.c",  "copyfile.c",  "cputime.c",
    "datec.c",     "dates.c",    "dateshb.c",   "datesx.c",
    "defpath.c",   "defpathu.c", "descend.c",   "dirdrive.c",
    "direct.c",    "diskspac.c", "disksphb.c",  "do.c",
    "empty.c",     "errapi.c",   "errapiu.c",   "errint.c",
    "errintlo.c",  "file.c",     "filebuf.c",   "filebufd.c",
    "filehb.c",    "filesys.c",  "fkmax.c",     "fmhb.c",
    "fnsplit.c",   "fscopy.c",   "fserr.c",     "fslink.c",
    "fssize.c",    "fstemp.c",   "gete.c",      "gt.c",
    "gtapi.c",     "gtapiu.c",   "gtchrmap.c",  "gtclip.c",
    "gtfunc.c",    "gtkbstat.c", "gtkeycod.c",
    "gttone.c",    "gx.c",       "hardcr.c",    "hbadler.c",
    "hbascii.c",   "hbbffnc.c",  "hbbfish.c",   "hbbfsock.c",
    "hbbit.c",     "hbbyte.c",   "hbcom.c",     "hbcomhb.c",
    "hbcrc.c",     "hbdef.c",    "hbdyn.c",     "hbdynhb.c",
    "hbfeof.c",    "hbfile.c",   "hbfilehc.c",  "hbgtcore.c",
    "hbhex.c",     "hbi18n1.c",  "hbinet.c",    "hbinetz.c",
    "hbjson.c",    "hblpp.c",    "hblpphb.c",   "hbmd5.c",
    "hbmd5enc.c",  "hbntos.c",   "hbproces.c",  "hbprocfn.c",
    "hbrand.c",    "hbrandom.c", "hbregex.c",   "hbregexc.c",
    "hbrunfun.c",  "hbsha1.c",   "hbsha1hm.c",  "hbsha2.c",
    "hbsha2hm.c",  "hbsocket.c", "hbsockhb.c",  "hbstrfmt.c",
    "hbstrsh.c",   "hbtoken.c",  "hbzlib.c",    "hbzlibc.c",
    "hbzlibgz.c",  "hbznet.c",   "hbzsock.c",   "idle.c",
    "inkey.c",     "inkeyapi.c", "iousr.c",     "is.c",
    "isprint.c",   "itemseri.c", "lang.c",      "langapi.c",
    "left.c",      "len.c",      "lennum.c",    "libnamec.c",
    "math.c",      "maxrow.c",   "memofile.c",  "minmax.c",
    "mlcfunc.c",   "mod.c",      "mouse53.c",   "mouseapi.c",
    "mousehb.c",   "mtran.c",    "natmsg.c",    "natmsgu.c",
    "net.c",       "netusr.c",   "oemansi.c",   "oldbox.c",
    "oldclear.c",  "pad.c",      "padx.c",      "philes.c",
    "philes53.c",  "rat.c",      "replic.c",    "right.c",
    "round.c",     "rtlshort.c", "run.c",       "samples.c",
    "saverest.c",  "scroll.c",   "scrrow.c",    "seconds.c",
    "setcolor.c",  "setcurs.c",  "setkey.c",    "setpos.c",
    "setposbs.c",  "sha1.c",     "sha1hmac.c",  "sha2.c",
    "sha2hmac.c",  "shadow.c",   "shadowu.c",   "soundex.c",
    "space.c",     "spfiles.c",  "str.c",       "strc.c",
    "strcase.c",   "strclear.c", "strmatch.c",  "strrepl.c",
    "strtoexp.c",  "strtran.c",  "strutf8.c",   "strxor.c",
    "strzero.c",   "stuff.c",    "substr.c",    "tone.c",
    "trace.c",     "transfrm.c", "trim.c",      "tscalara.c",
    "tscalarb.c",  "tscalarc.c", "tscalard.c",  "tscalarh.c",
    "tscalarl.c",  "tscalarn.c", "tscalarp.c",  "tscalars.c",
    "tscalart.c",  "tscalaru.c", "type.c",      "val.c",
    "valtostr.c",  "valtype.c",  "version.c",   "vfile.c",
    "word.c",      "xhelp.c",    "xsavescr.c",
};

// ---------------------------------------------------------------
// PRG source file lists (Phase 3 — from Makefiles)
// ---------------------------------------------------------------

const rtl_prg_srcs: []const []const u8 = &.{
    "achoice.prg",  "adir.prg",     "alert.prg",    "altd.prg",
    "browdb.prg",   "browse.prg",   "cdpdet.prg",   "checkbox.prg",
    "color53.prg",  "dbedit.prg",   "devoutp.prg",  "dircmd.prg",
    "dirscan.prg",  "einstv52.prg", "einstvar.prg", "einstvau.prg",
    "errsys.prg",   "getlist.prg",  "getsys.prg",   "getsys53.prg",
    "getsyshb.prg", "gui.prg",      "hbdoc.prg",    "hbfilehi.prg",
    "hbi18n2.prg",  "hbini.prg",    "input.prg",    "langcomp.prg",
    "langlgcy.prg", "libname.prg",  "listbox.prg",  "memoedit.prg",
    "memvarhb.prg", "menuto.prg",   "menusys.prg",  "objfunc.prg",
    "perfuncs.prg", "profiler.prg", "pushbtn.prg",  "radiobhb.prg",
    "radiobtn.prg", "radiogrp.prg", "readkey.prg",  "readvar.prg",
    "savebuff.prg", "scrollbr.prg", "setfunc.prg",  "setta.prg",
    "tclass.prg",   "tbcolumn.prg", "tbrowse.prg",  "tbrowsys.prg",
    "teditor.prg",  "text.prg",     "tget.prg",     "tgethb.prg",
    "tgetint.prg",  "tgetlist.prg", "tlabel.prg",   "tmenuitm.prg",
    "tmenusys.prg", "tobject.prg",  "tpersist.prg", "tpopup.prg",
    "tpopuphb.prg", "treport.prg",  "tscalar.prg",  "tsymbol.prg",
    "ttextlin.prg", "ttopbar.prg",  "typefile.prg", "valtoexp.prg",
    "vfilehi.prg",  "wait.prg",
};

const rdd_prg_srcs: []const []const u8 = &.{
    "dbdelim.prg",  "dbjoin.prg",   "dblist.prg",   "dbsdf.prg",
    "dbsort.prg",   "dbstrux.prg",  "dbstruxu.prg", "dbtotal.prg",
    "dbupdat.prg",  "rddord.prg",   "rddordu.prg",  "rddsys.prg",
};

const debug_prg_srcs: []const []const u8 = &.{
    "dbgbrwsr.prg", "dbghelp.prg",  "dbgmenu.prg",  "dbgtarr.prg",
    "dbgthsh.prg",  "dbgtinp.prg",  "dbgtmenu.prg", "dbgtmitm.prg",
    "dbgtobj.prg",  "dbgtwin.prg",  "dbgwa.prg",    "debugger.prg",
    "tbrwtext.prg",
};

const hbtest_prg_srcs: []const []const u8 = &.{
    "hbtest.prg",   "rt_array.prg", "rt_class.prg", "rt_date.prg",
    "rt_file.prg",  "rt_hvm.prg",   "rt_hvma.prg",  "rt_math.prg",
    "rt_misc.prg",  "rt_mt.prg",    "rt_str.prg",   "rt_stra.prg",
    "rt_trans.prg",
};
