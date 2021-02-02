let admin_psw="c1pR00t"
let user_psw="c1pUS3r"

db = db.getSiblingDB( "admin" );
db.createUser({
    user: "xAdmin", 
    pwd: admin_psw, 
    roles: ["root"]
});

let databases= ["active-sessions", "applicationLanguages"];

while(databases.length) { 
    let current_db = databases.shift(); 

    db = db.getSiblingDB( current_db );

    db.createUser({ 
        user: "appUser", 
        pwd: user_psw, 
        roles: ["readWrite"],
        customData: { installedBy: "app4linux setup script" }
    });
};