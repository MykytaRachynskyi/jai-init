JAILS_FILE_PATH :: "jails.json";

JAILS_FILE :: #string DONE
{
    "local_modules": [
        "src/modules",
        "modules",
        "vendor"
    ],
    "roots": [
        "src/main.jai",
        "build.jai"
    ],
    "build_root": "build.jai"
}
DONE
