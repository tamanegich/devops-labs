const mariadb = require("mariadb");
const { Command } = require("commander");

const program = new Command();
program
    .option("--db-host <host>", "MariaDB host", "localhost")
    .option("--db-port <number>", "MariaDB port", "3306")
    .option("--db-user <user>", "MariaDB user", "taskuser")
    .option("--db-password <pass>", "MariaDB password", "taskpassword")
    .option("--db-name <name>", "MariaDB database name", "taskdb")
    .parse(process.argv);

const opts = program.opts();

const migrations = [
    {
        version: 1,
        description: "Create tasks table",
        up: async (conn) => {
            await conn.query(`
                CREATE TABLE IF NOT EXISTS tasks (
                    id         INT UNSIGNED   NOT NULL AUTO_INCREMENT,
                    title      VARCHAR(255)   NOT NULL,
                    status     ENUM('pending','done') NOT NULL DEFAULT 'pending',
                    created_at DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (id)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
            `);
        },
    },
    //    future migrations gonna be here:
    //    {
    //        version: 2,
    //        description: "Add priority column",
    //        up: async (conn) => {
    //            await conn.query("ALTER TABLE tasks ADD COLUMN priority INT DEFAULT 0");
    //        },
    //    },
];

async function migrate() {
    const conn = await mariadb.createConnection({
        host: opts.dbHost,
        port: Number(opts.dbPort),
        user: opts.dbUser,
        password: opts.dbPassword,
        database: opts.dbName,
    });

    try {
        await conn.query(`
            CREATE TABLE IF NOT EXISTS _migrations (
                version     INT UNSIGNED NOT NULL,
                description VARCHAR(255) NOT NULL,
                applied_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (version)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        `);

        const applied = await conn.query("SELECT version FROM _migrations");
        const appliedVersions = new Set(applied.map((r) => Number(r.version)));

        const pending = migrations.filter(
            (m) => !appliedVersions.has(m.version),
        );

        if (pending.length === 0) {
            console.log("Database is up to date, no migrations to run.");
            return;
        }

        for (const migration of pending) {
            console.log(
                `Applying migration ${migration.version}: ${migration.description}...`,
            );
            await conn.beginTransaction();
            try {
                await migration.up(conn);
                await conn.query(
                    "INSERT INTO _migrations (version, description) VALUES (?, ?)",
                    [migration.version, migration.description],
                );
                await conn.commit();
                console.log(
                    `Migration ${migration.version} applied successfully.`,
                );
            } catch (err) {
                await conn.rollback();
                console.error(
                    `Migration ${migration.version} failed:`,
                    err.message,
                );
                process.exit(1);
            }
        }

        console.log("All migrations applied successfully.");
    } finally {
        await conn.end();
    }
}

migrate();
