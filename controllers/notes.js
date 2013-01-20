module.exports.note = function(req, res){
    getNotes = function(req, res) {
        var mysql      = require('../scripts/node_modules/mysql');
        var connection = mysql.createConnection({
            host     : 'localhost',
            user     : 'ge',
            password : 'ge',
            database  : 'ge',
        });

        var query = 'SELECT * FROM rechnung WHERE fk_id_og = 15';
        connection.connect();

        connection.query(query, function(err, rows, fields) {
            if (err) throw err;
            res.send(rows);
        });

        connection.end();
    };

    getNoteById = function(req, res, id) {
        var mysql      = require('../scripts/node_modules/mysql');
        var connection = mysql.createConnection({
            host     : 'localhost',
            user     : 'ge',
            password : 'ge',
            database  : 'ge',
        });


        //var query = 'SELECT * FROM rechnung WHERE id = ' + 14;
        var query = 'SELECT * FROM rechnung WHERE id = ' + id;
        console.log (query);
        connection.connect();

        connection.query(query, function(err, rows, fields) {
            if (err) throw err;
            res.send(rows[0]);
        });

        connection.end();
    };

    console.log ("0: " + req.params[0]);
    console.log ("1: " + req.params[1]);

    if (req.params[0] === "all") {
        this.getNotes(req, res);
    } else {
        this.getNoteById(req, res, req.params[0]);
    }
};