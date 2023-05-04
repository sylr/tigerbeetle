const builtin = @import("builtin");
const std = @import("std");

const Docs = @import("../docs_types.zig").Docs;
const run = @import("../shutil.zig").run;
const run_shell = @import("../shutil.zig").run_shell;
const script_filename = @import("../shutil.zig").script_filename;
const write_shell_newlines_into_single_line = @import("../shutil.zig").write_shell_newlines_into_single_line;

// Caller is responsible for resetting to a good cwd after this completes.
fn find_tigerbeetle_client_jar(arena: *std.heap.ArenaAllocator, root: []const u8) ![]const u8 {
    try std.os.chdir(root);

    var tries: usize = 2;
    var java_target_path: []const u8 = "";
    while (tries > 0) {
        if (std.fs.cwd().realpathAlloc(arena.allocator(), "src/clients/java/target")) |path| {
            std.debug.print("Found jar.\n", .{});
            java_target_path = path;
            break;
        } else |err| switch (err) {
            else => {
                std.debug.print("Could not find jar, rebuilding.\n", .{});

                var cmd = std.ArrayList(u8).init(arena.allocator());
                // First run general setup within already cloned repo
                try write_shell_newlines_into_single_line(&cmd, if (builtin.os.tag == .windows)
                    JavaDocs.developer_setup_pwsh_commands
                else
                    JavaDocs.developer_setup_sh_commands);

                try run_shell(arena, cmd.items);

                // Retry opening the directory now that we've run the install script.
                try std.os.chdir(root);
                tries -= 1;
            },
        }
    }

    var dir = try std.fs.cwd().openDir(java_target_path, .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(arena.allocator());
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (std.mem.endsWith(u8, entry.path, "-SNAPSHOT.jar")) {
            return std.fmt.allocPrint(
                arena.allocator(),
                "{s}/{s}",
                .{ java_target_path, entry.path },
            );
        }
    }

    std.debug.print("Could not find src/clients/java/target/**/*-SNAPSHOT.jar, run: cd src/clients/java && ./scripts/install.X)\n", .{});
    return error.JarFileNotfound;
}

fn java_current_commit_pre_install_hook(
    arena: *std.heap.ArenaAllocator,
    sample_root: []const u8,
    root: []const u8,
) !void {
    const jar_file = try find_tigerbeetle_client_jar(arena, root);
    // Generate a local maven package from a JAR.
    try run(arena, &[_][]const u8{
        "mvn",
        "deploy:deploy-file",
        try std.fmt.allocPrint(arena.allocator(), "-Durl=file://{s}", .{sample_root}),
        try std.fmt.allocPrint(arena.allocator(), "-Dfile={s}", .{jar_file}),
        "-DgroupId=com.tigerbeetle",
        "-DartifactId=tigerbeetle-java",
        "-Dpackaging=jar",
        "-Dversion=0.0.1-3431",
    });

    // Write out the local-settings.xml that points maven out our local package.
    const local_settings_xml_path = try std.fmt.allocPrint(
        arena.allocator(),
        "{s}/local-settings.xml",
        .{sample_root},
    );
    var local_settings_xml = try std.fs.cwd().createFile(
        local_settings_xml_path,
        .{ .truncate = true },
    );
    defer local_settings_xml.close();
    _ = try local_settings_xml.write(
        try std.fmt.allocPrint(
            arena.allocator(),
            \\<settings
            \\  xmlns="http://maven.apache.org/SETTINGS/1.0.0"
            \\  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
            \\  xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0 http://maven.apache.org/xsd/settings-1.0.0.xsd"
            \\>
            \\  <localRepository>
            \\    {s}
            \\  </localRepository>
            \\</settings>
        ,
            .{sample_root},
        ),
    );
}

fn local_command_hook(arena: *std.heap.ArenaAllocator, cmd: []const u8) ![]const u8 {
    return try std.mem.replaceOwned(
        u8,
        arena.allocator(),
        cmd,
        "mvn",
        "mvn -s local-settings.xml",
    );
}

pub const JavaDocs = Docs{
    .directory = "java",

    .markdown_name = "java",
    .extension = "java",
    .proper_name = "Java",

    .test_linux_docker_image = "alpine",

    .test_source_path = "src/main/java/",

    .name = "tigerbeetle-java",
    .description = 
    \\The TigerBeetle client for Java.
    \\
    \\[![javadoc](https://javadoc.io/badge2/com.tigerbeetle/tigerbeetle-java/javadoc.svg)](https://javadoc.io/doc/com.tigerbeetle/tigerbeetle-java)
    \\
    \\[![maven-central](https://img.shields.io/maven-central/v/com.tigerbeetle/tigerbeetle-java)](https://central.sonatype.com/namespace/com.tigerbeetle)
    ,

    .prerequisites = 
    \\* Java >= 11
    \\* Maven >= 3.6 (not strictly necessary but it's what our guides assume)
    ,

    .project_file_name = "pom.xml",
    .project_file = 
    \\<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    \\         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    \\  <modelVersion>4.0.0</modelVersion>
    \\
    \\  <groupId>com.tigerbeetle</groupId>
    \\  <artifactId>samples</artifactId>
    \\  <version>1.0-SNAPSHOT</version>
    \\
    \\  <properties>
    \\    <maven.compiler.source>11</maven.compiler.source>
    \\    <maven.compiler.target>11</maven.compiler.target>
    \\  </properties>
    \\
    \\  <build>
    \\    <plugins>
    \\      <plugin>
    \\        <groupId>org.apache.maven.plugins</groupId>
    \\        <artifactId>maven-compiler-plugin</artifactId>
    \\        <version>3.8.1</version>
    \\        <configuration>
    \\          <compilerArgs>
    \\            <arg>-Xlint:all,-options,-path</arg>
    \\          </compilerArgs>
    \\        </configuration>
    \\      </plugin>
    \\
    \\      <plugin>
    \\        <groupId>org.codehaus.mojo</groupId>
    \\        <artifactId>exec-maven-plugin</artifactId>
    \\        <version>1.6.0</version>
    \\        <configuration>
    \\          <mainClass>com.tigerbeetle.samples.Main</mainClass>
    \\        </configuration>
    \\      </plugin>
    \\    </plugins>
    \\  </build>
    \\
    \\  <dependencies>
    \\    <dependency>
    \\      <groupId>com.tigerbeetle</groupId>
    \\      <artifactId>tigerbeetle-java</artifactId>
    \\      <!-- Grab the latest commit from: https://repo1.maven.org/maven2/com/tigerbeetle/tigerbeetle-java/maven-metadata.xml -->
    \\      <version>0.0.1-3431</version>
    \\    </dependency>
    \\  </dependencies>
    \\</project> 
    ,

    .test_file_name = "Main",

    .install_sample_file = 
    \\package com.tigerbeetle.samples;
    \\
    \\import com.tigerbeetle.*;
    \\
    \\public final class Main {
    \\    public static void main(String[] args) {
    \\        System.out.println("Import ok!");
    \\    }
    \\}
    ,

    .install_prereqs = "apk add -U maven openjdk11",

    .current_commit_pre_install_hook = java_current_commit_pre_install_hook,
    .current_commit_post_install_hook = null,

    .install_commands = "mvn install",
    .build_commands = "mvn compile",
    .run_commands = "mvn exec:java",

    .current_commit_install_commands_hook = local_command_hook,
    .current_commit_build_commands_hook = local_command_hook,
    .current_commit_run_commands_hook = local_command_hook,

    .install_documentation = "",

    .examples = "",

    .client_object_example = 
    \\var tbAddress = System.getenv("TB_ADDRESS");
    \\Client client = new Client(
    \\  0,
    \\  new String[] {tbAddress.length() > 0 ? tbAddress : "3000"}
    \\);
    ,

    .client_object_documentation = 
    \\If you create a `Client` like this, don't forget to call
    \\`client.close()` when you are done with it. Otherwise you
    \\can use the
    \\[try-with-resources](https://docs.oracle.com/javase/tutorial/essential/exceptions/tryResourceClose.html)
    \\syntax:
    \\```java
    \\try (var client = new Client(...)) {
    \\  // Use client
    \\} catch (Exception e) {
    \\  // Handle exception
    \\}
    \\```
    ,

    .create_accounts_example = 
    \\AccountBatch accounts = new AccountBatch(1);
    \\accounts.add();
    \\accounts.setId(137);
    \\accounts.setUserData(UInt128.asBytes(new java.math.BigInteger("92233720368547758070")));
    \\accounts.setLedger(1);
    \\accounts.setCode(718);
    \\accounts.setFlags(0);
    \\
    \\CreateAccountResultBatch accountErrors = client.createAccounts(accounts);
    ,

    .create_accounts_documentation = 
    \\The 128-bit fields like `id` and `user_data` have a few
    \\overrides to make it easier to integrate. You can either
    \\pass in a long, a pair of longs (least and most
    \\significant bits), or a `byte[]`.
    \\
    \\There is also a `com.tigerbeetle.UInt128` helper with static
    \\methods for converting 128-bit little-endian unsigned integers
    \\between instances of `long`, `UUID`, `BigInteger` and `byte[]`.
    ,

    .account_flags_documentation = 
    \\To toggle behavior for an account, combine enum values stored in the
    \\`AccountFlags` object with bitwise-or:
    \\
    \\* `AccountFlags.LINKED`
    \\* `AccountFlags.DEBITS_MUST_NOT_EXCEED_CREDITS`
    \\* `AccountFlags.CREDITS_MUST_NOT_EXCEED_CREDITS`
    ,

    .account_flags_example = 
    \\accounts = new AccountBatch(3);
    \\
    \\// First account
    \\accounts.add();
    \\// Code to fill out fields for first account
    \\accounts.setFlags(AccountFlags.LINKED | AccountFlags.DEBITS_MUST_NOT_EXCEED_CREDITS);
    \\
    \\// Second account
    \\accounts.add();
    \\// Code to fill out fields for second account
    \\
    \\accountErrors = client.createAccounts(accounts);
    ,

    .create_accounts_errors_example = 
    \\accounts = new AccountBatch(3);
    \\
    \\// First account
    \\accounts.add();
    \\// Code to fill out fields for first account
    \\
    \\// Second account
    \\accounts.add();
    \\// Code to fill out fields for second account
    \\
    \\// Third account
    \\accounts.add();
    \\// Code to fill out fields for third account
    \\
    \\accountErrors = client.createAccounts(accounts);
    \\while (accountErrors.next()) {
    \\    switch (accountErrors.getResult()) {
    \\        case Exists:
    \\            System.err.printf("Account at %d already exists.\n",
    \\                accountErrors.getIndex());        
    \\            break;
    \\
    \\        default:
    \\            System.err.printf("Error creating account at %d: %s\n",
    \\                accountErrors.getIndex(),
    \\                accountErrors.getResult());
    \\            break;
    \\    }
    \\}
    ,

    .create_accounts_errors_documentation = "",

    .lookup_accounts_example = 
    \\IdBatch ids = new IdBatch(2);
    \\ids.add(137);
    \\ids.add(138);
    \\accounts = client.lookupAccounts(ids);
    ,

    .create_transfers_example = 
    \\TransferBatch transfers = new TransferBatch(1);
    \\transfers.add();
    \\transfers.setId(1);
    \\transfers.setDebitAccountId(1);
    \\transfers.setCreditAccountId(2);
    \\transfers.setUserData(2);
    \\transfers.setTimeout(0);
    \\transfers.setLedger(1);
    \\transfers.setCode(1);
    \\transfers.setFlags(0);
    \\transfers.setAmount(10);
    \\
    \\CreateTransferResultBatch transferErrors = client.createTransfers(transfers);
    ,

    .create_transfers_documentation = "",

    .create_transfers_errors_example = 
    \\while (transferErrors.next()) {
    \\    switch (transferErrors.getResult()) {
    \\        case ExceedsCredits:
    \\            System.err.printf("Transfer at %d exceeds credits.\n",
    \\                transferErrors.getIndex());        
    \\            break;
    \\
    \\        default:
    \\            System.err.printf("Error creating transfer at %d: %s\n",
    \\                transferErrors.getIndex(),
    \\                transferErrors.getResult());
    \\            break;
    \\    }
    \\}
    ,

    .create_transfers_errors_documentation = "",

    .no_batch_example = 
    \\for (int i = 0; i < transfers.length; i++) {
    \\  TransferBatch batch = new TransferBatch(1);
    \\  batch.add();
    \\  batch.setId(transfers[i].getId());
    \\  batch.setDebitAccountId(transfers[i].getDebitAccountId());
    \\  batch.setCreditAccountId(transfers[i].getCreditAccountId());
    \\
    \\  CreateTransferResultBatch errors = client.createTransfers(batch);
    \\  // error handling omitted
    \\}
    ,

    .batch_example = 
    \\var BATCH_SIZE = 8191;
    \\for (int i = 0; i < transfers.length; i += BATCH_SIZE) {
    \\  TransferBatch batch = new TransferBatch(BATCH_SIZE);
    \\
    \\  for (int j = 0; j < BATCH_SIZE && i + j < transfers.length; j++) {
    \\    batch.add();
    \\    batch.setId(transfers[i + j].getId());
    \\    batch.setDebitAccountId(transfers[i + j].getDebitAccountId());
    \\    batch.setCreditAccountId(transfers[i + j].getCreditAccountId());
    \\  }
    \\
    \\  CreateTransferResultBatch errors = client.createTransfers(batch);
    \\  // error handling omitted
    \\}
    ,

    .transfer_flags_documentation = 
    \\To toggle behavior for an account, combine enum values stored in the
    \\`TransferFlags` object with bitwise-or:
    \\
    \\* `TransferFlags.NONE`
    \\* `TransferFlags.LINKED`
    \\* `TransferFlags.PENDING`
    \\* `TransferFlags.POST_PENDING_TRANSFER`
    \\* `TransferFlags.VOID_PENDING_TRANSFER`
    ,

    .transfer_flags_link_example = 
    \\transfers = new TransferBatch(2);
    \\
    \\// First transfer
    \\transfers.add();
    \\// Code to fill out fields for first transfer
    \\transfers.setFlags(TransferFlags.LINKED);
    \\
    \\// Second transfer
    \\transfers.add();
    \\// Code to fill out fields for second transfer
    \\transferErrors = client.createTransfers(transfers);
    ,

    .transfer_flags_post_example = 
    \\transfers = new TransferBatch(1);
    \\
    \\// First transfer
    \\transfers.add();
    \\// Code to fill out fields for first transfer
    \\transfers.setFlags(TransferFlags.POST_PENDING_TRANSFER);
    \\transferErrors = client.createTransfers(transfers);
    ,

    .transfer_flags_void_example = 
    \\transfers = new TransferBatch(1);
    \\
    \\// First transfer
    \\transfers.add();
    \\// Code to fill out fields for first transfer
    \\transfers.setFlags(TransferFlags.VOID_PENDING_TRANSFER);
    \\transferErrors = client.createTransfers(transfers);
    ,

    .lookup_transfers_example = 
    \\ids = new IdBatch(2);
    \\ids.add(1);
    \\ids.add(2);
    \\transfers = client.lookupTransfers(ids);
    ,

    .linked_events_example = 
    \\transfers = new TransferBatch(10);
    \\
    \\// An individual transfer (successful):
    \\transfers.add();
    \\transfers.setId(1);
    \\
    \\// A chain of 4 transfers (the last transfer in the chain closes the chain with linked=false):
    \\transfers.add();
    \\transfers.setId(2); // Commit/rollback.
    \\transfers.setFlags(TransferFlags.LINKED);
    \\
    \\transfers.add();
    \\transfers.setId(3); // Commit/rollback.
    \\transfers.setFlags(TransferFlags.LINKED);
    \\
    \\transfers.add();
    \\transfers.setId(2); // Fail with exists
    \\transfers.setFlags(TransferFlags.LINKED);
    \\
    \\transfers.add();
    \\transfers.setId(4); // Fail without committing
    \\
    \\// An individual transfer (successful):
    \\// This should not see any effect from the failed chain above.
    \\transfers.add();
    \\transfers.setId(2);
    \\
    \\// A chain of 2 transfers (the first transfer fails the chain):
    \\transfers.add();
    \\transfers.setId(2);
    \\transfers.setFlags(TransferFlags.LINKED);
    \\
    \\transfers.add();
    \\transfers.setId(3);
    \\
    \\// A chain of 2 transfers (successful):
    \\transfers.add();
    \\transfers.setId(3);
    \\transfers.setFlags(TransferFlags.LINKED);
    \\
    \\transfers.add();
    \\transfers.setId(4);
    \\
    \\transferErrors = client.createTransfers(transfers);
    ,

    .developer_setup_sh_commands = 
    \\cd src/clients/java
    \\./scripts/install.sh
    \\if [ "$TEST" = "true" ]; then mvn test; else echo "Skipping client unit tests"; fi
    ,

    .developer_setup_pwsh_commands = 
    \\cd src/clients/java
    \\.\scripts\install.bat
    \\if ($env:TEST -eq 'true') { mvn test } else { echo "Skipping client unit test" }
    ,

    .test_main_prefix = 
    \\package com.tigerbeetle.samples;
    \\
    \\import com.tigerbeetle.*;
    \\public final class Main {
    \\  public static void main(String[] args) throws com.tigerbeetle.RequestException {
    ,

    .test_main_suffix = "} }",
};
