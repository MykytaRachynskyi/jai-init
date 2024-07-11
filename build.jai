#import "Basic";
#import "Compiler";
#import "Process";
#import "File";
#import "String";

build :: () {
    w := compiler_create_workspace("Target Program");
    if !w {
        print("Workspace creation failed.\n");
        return;
    }

    options := get_build_options(w);
    options.output_executable_name = get_basename_and_path(#file);

    new_path: [..] string;
    array_add(*new_path, ..options.import_path);
    array_add(*new_path, "src/modules");
    array_add(*new_path, "vendor");
    options.import_path = new_path;
    // output
    {
        options.output_executable_name = "jai-init";
        options.output_path = "out";
    }
    set_build_options(options, w);

    compiler_begin_intercept(w);
    add_build_file("src/main.jai", w);
    message_loop();
    compiler_end_intercept(w);

    set_build_options_dc(.{do_output=false, write_added_strings=false});
}

#run build();

message_loop :: () {
    while true {
        message := compiler_wait_for_message();

        if message.kind == {
            case .FILE;
            case .IMPORT;
            case .FAILED_IMPORT;
            case .PHASE;
            case .TYPECHECKED;
            case .DEBUG_DUMP;
            case .ERROR;
            case .PERFORMANCE_REPORT;
            case .COMPLETE;
            print("Compilation done.");
            return;
        }
    }
}
