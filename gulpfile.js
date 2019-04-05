const gulp = require("gulp");
const file = require("gulp-file");
const ts = require("gulp-typescript");
const rollup = require("rollup");
const terser = require("terser");

function compile() {
    const program = gulp.src("./src/*.ts")
        .pipe(ts({
            target: "es2015",
            module: "es2015",
            strict: true,
            noUnusedLocals: true,
            noUnusedParameters: true,
            noImplicitReturns: true,
            noFallthroughCasesInSwitch: true
        }));
    return program.js.pipe(gulp.dest("./tmp/"));
};

function copyjs() {
    return gulp.src("./src/*.js")
        .pipe(gulp.dest("./tmp/"));
};

async function bundle() {
    const bundle = await rollup.rollup({input: "./tmp/index.js"});
    let {output} = await bundle.generate({format: "es"});

    let code;
    for (const chunk of output)
        if (!chunk.isAsset) code = chunk.code;

    const minified = terser.minify(code, {
        compress: {},
        mangle: {keep_fnames: true},
        output: {beautify: false, max_line_len: 0}
    });
    code = minified.code;

    return file("opma.js", code)
        .pipe(gulp.dest("./dist/"));
};

exports.default = gulp.series(compile, copyjs, bundle);
