#import "Basic";
#import "File";
#import "File_Utilities";
#import "String";

#load "main_file.jai";
#load "jails_file.jai";
#load "build_file.jai";

ItemToBeCreated :: struct {
    path: string;
    contents: string;
    is_dir: bool;
}

main :: () {
    defer reset_temporary_storage();

    context.allocator = temp;

    items_to_be_created: [..]ItemToBeCreated;

    cwd := get_working_directory();
    replace_chars(cwd, "\\", #char "/");

    // Create build file
    {
        cwd_path := parse_path(cwd);

        if cwd_path.words.count < 2 {
            write_string(tprint("Invalid cwd path: %\n", cwd_path), to_standard_error = true); 
            return;
        }

        exe_name := cwd_path.words[cwd_path.words.count - 1];
        print("%\n", exe_name);

        build_file_contents := replace(BUILD_FILE, EXE_NAME_STUB, exe_name);
        defer free(build_file_contents);

        array_add(*items_to_be_created, .{ BUILD_FILE_PATH, build_file_contents, false });
    }

    array_add(*items_to_be_created, .{ JAILS_FILE_PATH, JAILS_FILE, false });
    array_add(*items_to_be_created, .{ MAIN_FILE_PATH, MAIN_FILE, false });

    array_add(*items_to_be_created, .{ "vendor", .{}, true });
    array_add(*items_to_be_created, .{ "out", .{}, true });

    print_items(*items_to_be_created, cwd);

    BUFFER_SIZE :: 1024;
    buffer: [BUFFER_SIZE] u8;
    input: string;
    input.data = buffer.data;

    while true {
        print("\nWould you like to create these files and directories? [y/n]: ");
        // @Incomplete: Jai doesn't have an abstraction for reading from stdin yet...
        #if OS == .WINDOWS {
            #import "Windows";
            handle := GetStdHandle(STD_INPUT_HANDLE);
            bytes_read: u32;
            success := ReadFile(handle, buffer.data + input.count, cast(u32) (buffer.count - input.count), *bytes_read, null);
        } else {
            bytes_read := read(STDIN_FILENO, buffer.data + input.count, cast(u64) (buffer.count - input.count));
            if bytes_read < 0 {
                log_error("Couldn't read from stdin");
            }
        }

        input.count += bytes_read;

        if bytes_read {
            input = trim(input);
            if equal(input, "Y") || equal(input, "y") {
                create_items(*items_to_be_created);
                break;
            }
            else if equal(trim(input), "N") || equal(trim(input), "n") {
                print("Aborting. No files were created.\n");
                return;
            }
            else {
                print("Unrecognized input: %\n", input);
                input.count = 0;
            }
        }
    }
}

print_items :: (items: *[..]ItemToBeCreated, cwd: string) {
    string_builder: String_Builder;
    init_string_builder(*string_builder, 4096);
    defer reset(*string_builder);

    print("Files and directories that will be created:\n");

    for <<items {
        append(*string_builder, cwd);

        if !starts_with(it.path, "/") {
            append(*string_builder, "/");
        }

        append(*string_builder, it.path);
        print("%\n", builder_to_string(*string_builder));
    }

}

create_items :: (items: *[..]ItemToBeCreated) {

    print("\n");

    string_builder: String_Builder;
    init_string_builder(*string_builder, 4096);

    for <<items {
        path := parse_path(it.path); 

        if path.words.count > 1 { 
            for i: 0..path.words.count - 2 {
                append(*string_builder, path.words[i]);
                append(*string_builder, "/");
            }

            make_directory_if_it_does_not_exist(builder_to_string(*string_builder), true);
        }

        if it.is_dir {
            if !file_exists(it.path) {
                created := make_directory_if_it_does_not_exist(it.path);
            }
            else {
                print("Directory % already exists. Not creating a new one.\n", it.path);
            }
        }
        else {
            write_file_if_does_not_exist(it.path, it.contents);
        }
   }
}

write_file_if_does_not_exist :: (file_path: string, contents: string) {
    path := file_path;

    if starts_with(path, "/") {
        path.data += 1;
    }

    if !file_exists(path) {
        if !write_entire_file(path, contents) {
            write_string(tprint("Failed to create file %.\n", path), to_standard_error = true); 
            return;
        }
    }
    else {
        print("File % already exists. Not creating a new one.\n", path);
    }
}
