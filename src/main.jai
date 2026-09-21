#import "Basic";
#import "File";
#import "File_Utilities";
#import "String";
#import "Command_Line";

#load "main_file.jai";
#load "jails_file.jai";
#load "build_file.jai";
#load "gitignore_file.jai";

Arguments :: struct {
    name:  string; @"?Project name used as the output .exe name. Defaults to the current directory name. Can also be passed as a free argument.";
    y:     bool;   @"?Create files without asking for confirmation.";
    force: bool;   @"?Overwrite existing files instead of skipping them.";
}

ItemToBeCreated :: struct {
    path: string;
    contents: string;
    is_dir: bool;
}

Create_Stats :: struct {
    created: int;
    skipped: int;
    failed:  int;
}

main :: () {
    defer reset_temporary_storage();

    context.allocator = temp;

    success, args, is_set, free_args := parse_arguments(Arguments, Default_Argument_Flags | .SHOW_HELP_ON_ERROR);
    if !success return;

    exe_name, name_ok := resolve_project_name(args, is_set, free_args);
    if !name_ok return;

    if !is_valid_project_name(exe_name) {
        write_string(tprint("Invalid project name '%'. Use letters, digits, '_', '-', or '.'.\n", exe_name), to_standard_error = true);
        return;
    }

    items_to_be_created: [..]ItemToBeCreated;

    cwd := get_working_directory();
    replace_chars(cwd, "\\", #char "/");

    build_file_contents := replace(BUILD_FILE, EXE_NAME_STUB, exe_name);
    array_add(*items_to_be_created, .{ BUILD_FILE_PATH, build_file_contents, false });
    array_add(*items_to_be_created, .{ JAILS_FILE_PATH, JAILS_FILE, false });
    array_add(*items_to_be_created, .{ MAIN_FILE_PATH, MAIN_FILE, false });
    array_add(*items_to_be_created, .{ GITIGNORE_FILE_PATH, GITIGNORE_FILE, false });
    array_add(*items_to_be_created, .{ "src/modules", .{}, true });
    array_add(*items_to_be_created, .{ "vendor", .{}, true });
    array_add(*items_to_be_created, .{ "out", .{}, true });

    print("Project name / executable: %\n\n", exe_name);
    print_items(*items_to_be_created, cwd);

    if !args.y {
        if !confirm_create() {
            print("Aborting. No files were created.\n");
            return;
        }
    }

    stats := create_items(*items_to_be_created, args.force);
    print_create_summary(stats);

    if stats.failed == 0 && stats.created > 0 {
        print("\nNext: jai build.jai\n");
    }
}

resolve_project_name :: (args: Arguments, is_set: Is_Set(Arguments), free_args: [] string) -> (name: string, ok: bool) {
    if is_set.name && free_args.count {
        write_string("Pass the project name either as -name <name> or as a free argument, not both.\n", to_standard_error = true);
        return "", false;
    }

    if free_args.count > 1 {
        write_string("Too many free arguments. Expected at most one project name.\n", to_standard_error = true);
        return "", false;
    }

    if is_set.name {
        if !args.name.count {
            write_string("Project name given with -name must not be empty.\n", to_standard_error = true);
            return "", false;
        }
        return args.name, true;
    }

    if free_args.count == 1 {
        if !free_args[0].count {
            write_string("Project name must not be empty.\n", to_standard_error = true);
            return "", false;
        }
        return free_args[0], true;
    }

    cwd := get_working_directory();
    replace_chars(cwd, "\\", #char "/");
    cwd_path := parse_path(cwd);

    if !cwd_path.words.count {
        write_string(tprint("Invalid cwd path: %\n", cwd), to_standard_error = true);
        return "", false;
    }

    return cwd_path.words[cwd_path.words.count - 1], true;
}

is_valid_project_name :: (name: string) -> bool {
    if !name.count return false;

    for name {
        c := it;
        is_alpha := (c >= #char "A" && c <= #char "Z") || (c >= #char "a" && c <= #char "z");
        is_digit := c >= #char "0" && c <= #char "9";
        is_ok_symbol := c == #char "_" || c == #char "-" || c == #char ".";
        if !(is_alpha || is_digit || is_ok_symbol) return false;
    }

    return true;
}

confirm_create :: () -> bool {
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
            return false;
        }
        if bytes_read == 0 {
            write_string("No input received (EOF). Aborting.\n", to_standard_error = true);
            return false;
        }

        input.count += cast(s64) bytes_read;
        input = trim(input);

        if is_yes(input) return true;
        if is_no(input)  return false;

        print("Unrecognized input: %\n", input);
        input.count = 0;
    }

    return false;
}

is_yes :: (s: string) -> bool {
    return equal_nocase(s, "y") || equal_nocase(s, "yes");
}

is_no :: (s: string) -> bool {
    return equal_nocase(s, "n") || equal_nocase(s, "no");
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

create_items :: (items: *[..]ItemToBeCreated, force: bool) -> Create_Stats {
    print("\n");

    stats: Create_Stats;

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
            result := create_directory_item(it.path);
            update_stats(*stats, result);
        }
        else {
            result := write_file_item(it.path, it.contents, force);
            update_stats(*stats, result);
        }
    }

    return stats;
}

Item_Result :: enum {
    CREATED;
    SKIPPED;
    FAILED;
}

update_stats :: (stats: *Create_Stats, result: Item_Result) {
    if result == {
        case .CREATED; stats.created += 1;
        case .SKIPPED; stats.skipped += 1;
        case .FAILED;  stats.failed  += 1;
    }
}

create_directory_item :: (path: string) -> Item_Result {
    if file_exists(path) {
        print("Directory % already exists. Not creating a new one.\n", path);
        return .SKIPPED;
    }

    if make_directory_if_it_does_not_exist(path) {
        print("Created directory %.\n", path);
        return .CREATED;
    }

    write_string(tprint("Failed to create directory %.\n", path), to_standard_error = true);
    return .FAILED;
}

write_file_item :: (file_path: string, contents: string, force: bool) -> Item_Result {
    existed := file_exists(file_path);
    if existed && !force {
        print("File % already exists. Not creating a new one.\n", file_path);
        return .SKIPPED;
    }

    if !write_entire_file(file_path, contents) {
        write_string(tprint("Failed to create file %.\n", file_path), to_standard_error = true);
        return .FAILED;
    }

    if existed {
        print("Overwrote file %.\n", file_path);
    } else {
        print("Created file %.\n", file_path);
    }
    return .CREATED;
}

print_create_summary :: (stats: Create_Stats) {
    print("\nDone. Created: %, skipped: %, failed: %.\n", stats.created, stats.skipped, stats.failed);
}
