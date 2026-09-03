//! Minimal "TUI" — prints args + waits for input. Serves as a
//! login_binary stand-in for the ssh_tui_image smoke target.

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    println!("hello from ssh-tui-server's login binary");
    println!("args: {:?}", args);
    println!("type 'quit' to exit");
    let mut line = String::new();
    loop {
        line.clear();
        if std::io::stdin().read_line(&mut line).unwrap_or(0) == 0 {
            break;
        }
        let t = line.trim();
        if t == "quit" {
            break;
        }
        println!("you typed: {t}");
    }
}
