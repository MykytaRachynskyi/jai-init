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

        if !cwd_path.words.count {
            write_string(tprint("Invalid cwd path: %\n", cwd), to_standard_error = true);
            return;
        }

        exe_name := cwd_path.words[cwd_path.words.count - 1];

        // Lives until reset_temporary_storage via context.allocator = temp.
        build_file_contents := replace(BUILD_FILE, EXE_NAME_STUB, exe_name);
        array_add(*items_to_be_created, .{ BUILD_FILE_PATH, build_file_contents, false });
    }

    array_add(*items_to_be_created, .{ JAILS_FILE_PATH, JAILS_FILE, false });
    array_add(*items_to_be_created, .{ MAIN_FILE_PATH, MAIN_FILE, false });

    array_add(*items_to_be_created, .{ "src/modules", .{}, true });
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
        bytes_read := read_stdin(buffer.data + input.count, cast(s64) (buffer.count - input.count));
        if bytes_read < 0 {
            write_string("Couldn't read from stdin.\n", to_standard_error = true);
            return;
        }
        if bytes_read == 0 {
            write_string("No input received (EOF). Aborting.\n", to_standard_error = true);
            return;
        }

        input.count += cast(s64) bytes_read;
        input = trim(input);

        if equal(input, "Y") || equal(input, "y") {
            create_items(*items_to_be_created);
            break;
        }
        else if equal(input, "N") || equal(input, "n") {
            print("Aborting. No files were created.\n");
            return;
        }
        else {
            print("Unrecognized input: %\n", input);
            input.count = 0;
        }
    }
}

read_stdin :: (dest: *u8, max_bytes: s64) -> s64 {
    #if OS == .WINDOWS {
        #import "Windows";
        handle := GetStdHandle(STD_INPUT_HANDLE);
        bytes_read: u32;
        success := ReadFile(handle, dest, cast(u32) max_bytes, *bytes_read, null);
        if !success return -1;
        return cast(s64) bytes_read;
    } else {
        bytes_read := read(STDIN_FILENO, dest, cast(u64) max_bytes);
        return cast(s64) bytes_read;
    }
}

print_items :: (items: *[..]ItemToBeCreated, cwd: string) {
    string_builder: String_Builder;
    init_string_builder(*string_builder, 4096);
    defer reset(*string_builder);

    print("Files and directories that will be created:\n");

    for <<items {
        reset(*string_builder);

        append(*string_builder, cwd);
        if cwd.count == 0 || cwd[cwd.count - 1] != #char "/" {
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
    defer reset(*string_builder);

    for <<items {
        reset(*string_builder);

        path := parse_path(it.path);

        if path.words.count > 1 {
            for i: 0..path.words.count - 2 {
                if path.words[i].count == 0 continue;
                append(*string_builder, path.words[i]);
                append(*string_builder, "/");
            }

            parent := builder_to_string(*string_builder);
            if parent.count {
                make_directory_if_it_does_not_exist(parent, true);
            }
        }

        if it.is_dir {
            if !file_exists(it.path) {
                make_directory_if_it_does_not_exist(it.path);
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
    if !file_exists(file_path) {
        if !write_entire_file(file_path, contents) {
            write_string(tprint("Failed to create file %.\n", file_path), to_standard_error = true);
            return;
        }
    }
    else {
        print("File % already exists. Not creating a new one.\n", file_path);
    }
}
