import tkinter as tk
from tkinter import scrolledtext, messagebox
import socket
import ipaddress
import concurrent.futures
import threading
import urllib.request
import re
import html 
import webbrowser 

# Глобальный флаг для остановки потоков и счетчик
stop_event = threading.Event()
# Словарь для хранения состояния (свернуто/развернуто) для каждого IP
expanded_states = {}

def get_local_network():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        local_ip = s.getsockname()[0]
        s.close()
        network = ipaddress.IPv4Network(f"{local_ip}/24", strict=False)
        return str(network)
    except Exception:
        return "192.168.1.0/24"

def get_printer_name(ip):
    if stop_event.is_set(): return "Отменено"
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(1.0)
            s.connect((ip, 9100))
            s.sendall(b'\x1b%-12345X@PJL INFO ID\r\n\x1b%-12345X')
            response = s.recv(1024).decode('utf-8', errors='ignore')
            if '"' in response:
                name = response.split('"')[1].strip()
                if name: return name
    except:
        pass

    try:
        req = urllib.request.Request(f"http://{ip}", method="GET")
        with urllib.request.urlopen(req, timeout=1.0) as response:
            page_html = response.read().decode('utf-8', errors='ignore')
            match = re.search(r'<title>(.*?)</title>', page_html, re.IGNORECASE)
            if match:
                name = match.group(1).strip()
                name = html.unescape(name)
                name = name.replace(ip, '').strip(' -;')
                if name: return name
    except:
        pass
        
    return "Неизвестная модель"

def check_printer(ip):
    if stop_event.is_set():
        return None, None
        
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(0.5)
            s.connect((str(ip), 9100))
        name = get_printer_name(str(ip))
        return str(ip), name
    except:
        return None, None

# --- ЛОГИКА СВОРАЧИВАНИЯ / РАЗВОРАЧИВАНИЯ ---
def toggle_row(event, ip, widget):
    is_expanded = expanded_states.get(ip, False)
    content_tag = f"content_{ip}"
    toggle_tag = f"toggle_{ip}"

    # Находим, где именно нарисован плюсик или минусик
    ranges = widget.tag_ranges(toggle_tag)
    if ranges:
        start, end = ranges[0], ranges[1]
        # Удаляем старый знак
        widget.delete(start, end)

        if is_expanded:
            # СВОРАЧИВАЕМ: прячем текст (elide=True) и ставим [+]
            widget.tag_config(content_tag, elide=True)
            expanded_states[ip] = False
            widget.insert(start, "+", toggle_tag)
        else:
            # РАЗВОРАЧИВАЕМ: показываем текст (elide=False) и ставим [-]
            widget.tag_config(content_tag, elide=False)
            expanded_states[ip] = True
            widget.insert(start, "-", toggle_tag)

def add_clickable_result(ip, name):
    global expanded_states
    expanded_states[ip] = False # По умолчанию свернуто
    
    link_tag = f"link_{ip}"
    toggle_tag = f"toggle_{ip}"
    content_tag = f"content_{ip}"
    
    # Настраиваем стиль ссылки HTTP
    text_result.tag_config(link_tag, foreground="#2196F3", underline=True)
    text_result.tag_bind(link_tag, "<Button-1>", lambda e, url=ip: webbrowser.open(f"http://{url}"))
    text_result.tag_bind(link_tag, "<Enter>", lambda e: text_result.config(cursor="hand2"))
    text_result.tag_bind(link_tag, "<Leave>", lambda e: text_result.config(cursor="xterm"))
    
    # Настраиваем стиль кнопки [+]/[-]
    text_result.tag_config(toggle_tag, foreground="#2196F3", font=("Consolas", 10, "bold"))
    text_result.tag_bind(toggle_tag, "<Button-1>", lambda e, addr=ip: toggle_row(e, addr, text_result))
    text_result.tag_bind(toggle_tag, "<Enter>", lambda e: text_result.config(cursor="hand2"))
    text_result.tag_bind(toggle_tag, "<Leave>", lambda e: text_result.config(cursor="xterm"))

    # Настраиваем скрытый контент (сразу прячем его)
    text_result.tag_config(content_tag, elide=True)
    
    # Строка 1: Черные скобки, синий кликабельный плюс, IP и Имя
    text_result.insert(tk.END, "[")
    text_result.insert(tk.END, "+", toggle_tag)
    text_result.insert(tk.END, f"] {ip}  {name}\n")
    
    # Строка 2: Невидимый (пока) блок со ссылкой HTTP
    text_result.insert(tk.END, "       ", content_tag)
    text_result.insert(tk.END, f"HTTP, {name} {ip}\n", (link_tag, content_tag))
    
    text_result.see(tk.END)

def update_progress_label(current, total):
    label_progress.config(text=f"Прогресс: {current} / {total}")

def run_scan(network_cidr):
    try:
        network = ipaddress.ip_network(network_cidr, strict=False)
    except ValueError:
        root.after(0, lambda: text_result.insert(tk.END, "[-] Ошибка: Неверный формат сети.\n"))
        root.after(0, reset_buttons)
        return

    hosts = list(network.hosts())
    total_hosts = len(hosts)
    workers_count = 250 if total_hosts > 1000 else 50
    
    if total_hosts > 1000:
        root.after(0, lambda: text_result.insert(tk.END, f"[*] Большой диапазон ({total_hosts} адресов). Это займет время...\n"))

    printers_found = 0
    progress_counter = 0
    
    root.after(0, lambda: update_progress_label(0, total_hosts))
    
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers_count) as executor:
        future_to_ip = {executor.submit(check_printer, ip): ip for ip in hosts}
        
        for future in concurrent.futures.as_completed(future_to_ip):
            if stop_event.is_set():
                for f in future_to_ip:
                    f.cancel()
                root.after(0, lambda: text_result.insert(tk.END, "\n[!] Сканирование прервано пользователем.\n"))
                root.after(0, lambda: text_result.see(tk.END))
                break
                
            ip, name = future.result()
            if ip:
                root.after(0, add_clickable_result, ip, name)
                printers_found += 1
            
            # Обновляем прогресс
            progress_counter += 1
            if progress_counter % 10 == 0 or progress_counter == total_hosts:
                root.after(0, update_progress_label, progress_counter, total_hosts)
                
    if not stop_event.is_set():
        root.after(0, lambda: text_result.insert(tk.END, f"\n[*] Сканирование завершено. Найдено: {printers_found}\n"))
        root.after(0, lambda: text_result.see(tk.END))
        
    root.after(0, reset_buttons)

def start_scan_thread():
    current_ip = entry_ip.get()
    if current_ip.endswith('/16') or '.0.0' in current_ip:
        network_24 = get_local_network()
    else:
        try:
            network_24 = str(ipaddress.IPv4Network(current_ip, strict=False))
        except:
            network_24 = get_local_network()
        
    entry_ip.delete(0, tk.END)
    entry_ip.insert(0, network_24)
    prepare_and_run(network_24)

def start_wide_scan_thread():
    current_ip = entry_ip.get()
    try:
        ip_obj = ipaddress.IPv4Network(current_ip, strict=False)
        network_16 = str(ip_obj.supernet(new_prefix=16))
    except:
        network_16 = "192.168.0.0/16"
    
    entry_ip.delete(0, tk.END)
    entry_ip.insert(0, network_16)
    prepare_and_run(network_16)

def prepare_and_run(network_cidr):
    stop_event.clear()
    expanded_states.clear() # Очищаем словарь с плюсиками при новом скане
    text_result.delete(1.0, tk.END)
    text_result.insert(tk.END, f"[*] Сканирую сеть: {network_cidr}...\n\n")
    
    btn_scan.config(state=tk.DISABLED)
    btn_scan_16.config(state=tk.DISABLED)
    btn_stop.config(state=tk.NORMAL)
    
    thread = threading.Thread(target=run_scan, args=(network_cidr,), daemon=True)
    thread.start()

def stop_scan():
    stop_event.set()
    btn_stop.config(state=tk.DISABLED)
    text_result.insert(tk.END, "\n[~] Останавливаю процессы, подождите пару секунд...\n")
    text_result.see(tk.END)

def copy_all_results():
    root.clipboard_clear()
    # Получаем весь текст (включая скрытый elide=True) для удобства
    full_text = text_result.get(1.0, tk.END)
    root.clipboard_append(full_text)
    messagebox.showinfo("Скопировано", "Все результаты успешно скопированы!\n\nТеперь вы можете вставить их куда угодно (Ctrl+V).")

# --- Настройка графического интерфейса ---
root = tk.Tk()
root.title("Сетевой Сканер Принтеров")
root.geometry("540x580") 
root.resizable(False, False)

label_ip = tk.Label(root, text="Подсеть для сканирования:", font=("Arial", 10))
label_ip.pack(pady=(10, 0))

entry_ip = tk.Entry(root, font=("Arial", 12), width=20, justify="center")
entry_ip.insert(0, get_local_network()) 
entry_ip.pack(pady=5)

label_hint = tk.Label(root, text="Скан (/24) — быстрый поиск в обычной локальной сети.\nСкан (/16) — поиск по связанным сетям (туннели, VPN, Mikrotik).", 
                      font=("Arial", 9), fg="#555555", justify="center")
label_hint.pack(pady=(5, 5))

label_progress = tk.Label(root, text="Прогресс: 0 / 0", font=("Arial", 9, "bold"), fg="#1976D2")
label_progress.pack()

frame_buttons = tk.Frame(root)
frame_buttons.pack(pady=5)

btn_scan = tk.Button(frame_buttons, text="Скан (/24)", font=("Arial", 10, "bold"), bg="#4CAF50", fg="white", width=12, command=start_scan_thread)
btn_scan.grid(row=0, column=0, padx=5)

btn_scan_16 = tk.Button(frame_buttons, text="Скан (/16)", font=("Arial", 10, "bold"), bg="#2196F3", fg="white", width=12, command=start_wide_scan_thread)
btn_scan_16.grid(row=0, column=1, padx=5)

btn_stop = tk.Button(frame_buttons, text="Остановить", font=("Arial", 10, "bold"), bg="#e0e0e0", fg="#d32f2f", width=12, command=stop_scan, state=tk.DISABLED)
btn_stop.grid(row=0, column=2, padx=5)

def reset_buttons():
    btn_scan.config(state=tk.NORMAL)
    btn_scan_16.config(state=tk.NORMAL)
    btn_stop.config(state=tk.DISABLED)

text_result = scrolledtext.ScrolledText(root, width=65, height=15, font=("Consolas", 10))
text_result.pack(pady=5)

# --- ЖЕЛЕЗОБЕТОННЫЙ ФИКС КОПИРОВАНИЯ И МЕНЮ ---
def copy_selected(event=None):
    try:
        root.clipboard_clear()
        root.clipboard_append(text_result.get(tk.SEL_FIRST, tk.SEL_LAST))
    except tk.TclError:
        pass
    return "break"

def handle_keypress(event):
    if (event.state & 0x0004) and event.keycode == 67:
        copy_selected()
        return "break"

context_menu = tk.Menu(text_result, tearoff=0)
context_menu.add_command(label="Копировать выделенное", command=copy_selected)
context_menu.add_command(label="Выбрать всё", command=lambda: text_result.tag_add(tk.SEL, "1.0", tk.END))

def show_context_menu(event):
    context_menu.tk_popup(event.x_root, event.y_root)

text_result.bind("<Button-3>", show_context_menu)
text_result.bind("<Key>", handle_keypress)
text_result.bind("<Control-c>", copy_selected)
text_result.bind("<Control-C>", copy_selected)
# ----------------------------------------------

btn_copy = tk.Button(root, text="Скопировать всё окно", font=("Arial", 10, "bold"), bg="#ffeb3b", fg="black", command=copy_all_results)
btn_copy.pack(pady=5)

root.mainloop()