#import "Basic";
#import "File";
#import "File_Utilities";
#import "String";

#load "main_file.jai";
#load "jails_file.jai";
#load "build_file.jai";

MAIN_FILE_PATH :: "/src/main.jai";
BUILD_FILE_PATH :: "/build.jai";
JAILS_FILE_PATH :: "/jails.json";

main :: () {

    string_builder: String_Builder;
    init_string_builder(*string_builder, 4096);

    cwd := get_working_directory();

    // Create build file
    {
        append(*string_builder, cwd);
        append(*string_builder, BUILD_FILE_PATH);

        replace_chars(cwd, "\\", #char "/");
        cwd_path := parse_path(cwd);
        if cwd_path.words.count < 2 {
            write_string(tprint("Invalid cwd path: %", cwd_path), to_standard_error = true); 
            return;
        }

        exe_name := cwd_path.words[cwd_path.words.count - 1];

        build_file_contents := replace(BUILD_FILE, EXE_NAME_STUB, exe_name);

        file_path := builder_to_string(*string_builder);
        if !write_entire_file(file_path, build_file_contents) {
            write_string("Failed to create the 'build.jai' file.", to_standard_error = true); 
            return;
        }
    }

    // Create jails file
    {
        append(*string_builder, cwd);
        append(*string_builder, JAILS_FILE_PATH);

        file_path := builder_to_string(*string_builder);
        if !write_entire_file(file_path, JAILS_FILE) {
            write_string("Failed to create the 'jails.json' file.", to_standard_error = true); 
            return;
        }
    }

    // Create main file
    {
        append(*string_builder, cwd);
        append(*string_builder, MAIN_FILE_PATH);

        make_directory_if_it_does_not_exist("src");

        file_path := builder_to_string(*string_builder);
        if !write_entire_file(file_path, MAIN_FILE) {
            write_string("Failed to create the 'main.jai' file.", to_standard_error = true); 
            return;
        }
    }

    make_directory_if_it_does_not_exist("vendor");
    make_directory_if_it_does_not_exist("out");
}
