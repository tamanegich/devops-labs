const express = require("express");
const mariadb = require("mariadb");
const cors = require("cors");
const { Command } = require("commander");

const app = express();
app.use(express.json());
app.use(cors());

const program = new Command();
program
    .option("--port <number>", "API server port", "3000")
    .option("--db-host <host>", "MariaDB host", "localhost")
    .option("--db-port <number>", "MariaDB port", "3306")
    .option("--db-user <user>", "MariaDB user", "taskuser")
    .option("--db-password <pass>", "MariaDB password", "taskpassword")
    .option("--db-name <name>", "MariaDB database name", "taskdb")
    .parse(process.argv);

const opts = program.opts();

const pool = mariadb.createPool({
    host: opts.dbHost,
    port: Number(opts.dbPort),
    user: opts.dbUser,
    password: opts.dbPassword,
    database: opts.dbName,
    connectionLimit: 5,
});

function respond(req, res, status, data) {
    if (req.accepts("html")) {
        res.status(status).send(toHtml(data));
    } else {
        res.status(status).json(data);
    }
}

function toHtml(data) {
    if (Array.isArray(data)) {
        const headers = Object.keys(data[0] || {});
        const rows = data
            .map(
                (row) =>
                    `<tr>${headers.map((h) => `<td>${row[h]}</td>`).join("")}</tr>`,
            )
            .join("");
        return `<html><body><table border="1"><thead><tr>${headers.map((h) => `<th>${h}</th>`).join("")}</tr></thead><tbody>${rows}</tbody></table></body></html>`;
    }
    if (typeof data === "object") {
        const rows = Object.entries(data)
            .map(([k, v]) => `<tr><th>${k}</th><td>${v}</td></tr>`)
            .join("");
        return `<html><body><table border="1"><tbody>${rows}</tbody></table></body></html>`;
    }
    return `<html><body><p>${data}</p></body></html>`;
}

app.get("/health/alive", (req, res) => {
    respond(req, res, 200, "OK");
});

app.get("/health/ready", async (req, res) => {
    let conn;
    try {
        conn = await pool.getConnection();
        await conn.query("SELECT 1");
        respond(req, res, 200, "OK");
    } catch (err) {
        respond(req, res, 500, {
            status: "error",
            message: "Database connection failed",
            detail: err.message,
        });
    } finally {
        if (conn) conn.release();
    }
});

app.get("/tasks", async (req, res) => {
    let conn;
    try {
        conn = await pool.getConnection();
        const rows = await conn.query(
            "SELECT id, title, status, created_at FROM tasks ORDER BY created_at DESC",
        );
        respond(req, res, 200, rows);
    } catch (err) {
        console.error(err);
        respond(req, res, 500, {
            error: "Failed to fetch tasks",
            detail: err.message,
        });
    } finally {
        if (conn) conn.release();
    }
});

app.post("/tasks", async (req, res) => {
    const { title } = req.body;
    if (!title || !title.trim()) {
        return respond(req, res, 400, { error: "title is required" });
    }
    let conn;
    try {
        conn = await pool.getConnection();
        const result = await conn.query(
            "INSERT INTO tasks (title, status) VALUES (?, 'pending')",
            [title.trim()],
        );
        const [task] = await conn.query(
            "SELECT id, title, status, created_at FROM tasks WHERE id = ?",
            [result.insertId],
        );
        respond(req, res, 201, task);
    } catch (err) {
        console.error(err);
        respond(req, res, 500, {
            error: "Failed to create task",
            detail: err.message,
        });
    } finally {
        if (conn) conn.release();
    }
});

app.post("/tasks/:id/done", async (req, res) => {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) {
        return respond(req, res, 400, { error: "Invalid task id" });
    }
    let conn;
    try {
        conn = await pool.getConnection();
        const result = await conn.query(
            "UPDATE tasks SET status = 'done' WHERE id = ?",
            [id],
        );
        if (result.affectedRows === 0) {
            return respond(req, res, 404, { error: "Task not found" });
        }
        const [task] = await conn.query(
            "SELECT id, title, status, created_at FROM tasks WHERE id = ?",
            [id],
        );
        respond(req, res, 200, task);
    } catch (err) {
        console.error(err);
        respond(req, res, 500, {
            error: "Failed to update task",
            detail: err.message,
        });
    } finally {
        if (conn) conn.release();
    }
});

const PORT = Number(opts.port);
app.listen(PORT, () =>
    console.log(`API listening on http://localhost:${PORT}`),
);
