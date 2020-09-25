library_path = get(ENV, "LD_LIBRARY_PATH", "")
include_path = get(ENV, "C_INCLUDE_PATH", "")
run(`gcc -fPIC --shared -I$(include_path) -L$(library_path) ../src/remote_files.c -o remote_files.dylib -lssh`)
