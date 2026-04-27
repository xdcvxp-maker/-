import json import logging from telegram import Update, ReplyKeyboardMarkup, InlineKeyboardButton, InlineKeyboardMarkup from telegram.ext import ( Application, CommandHandler, MessageHandler, CallbackQueryHandler, ConversationHandler, ContextTypes, filters, )

Логирование для удобной отладки
logging.basicConfig( format="%(asctime)s - %(name)s - %(levelname)s - %(message)s", level=logging.INFO ) logger = logging.getLogger(name)

Состояния только для регистрационного диалога
AWAIT_REG_CONFIRM, AWAIT_NAME = range(2)

Файл, где будем хранить всех пользователей и их данные
DB_FILE = "users.json"

------------------------------------------------------------
Работа с JSON-хранилищем
------------------------------------------------------------
def load_users(): """Загружаем всех пользователей из файла, если файла нет — возвращаем пустой словарь.""" try: with open(DB_FILE, "r", encoding="utf-8") as f: return json.load(f) except (FileNotFoundError, json.JSONDecodeError): return {}

def save_users(users): """Сохраняем словарь пользователей в файл.""" with open(DB_FILE, "w", encoding="utf-8") as f: json.dump(users, f, ensure_ascii=False, indent=2)

def get_user_data(user_id): """Получить данные пользователя по его Telegram ID.""" return load_users().get(str(user_id))

def save_user_data(user_id, data): """Сохранить/обновить данные конкретного пользователя.""" users = load_users() users[str(user_id)] = data save_users(users)

------------------------------------------------------------
Глобальный словарь состояний для логики главного меню и подменю
Возможные значения:
'main' – обычный режим
'awaiting_note' – ждём текст новой заметки
'awaiting_delete_note' – ждём номер заметки для удаления
'awaiting_todo' – ждём текст новой задачи
'awaiting_delete_todo' – ждём номер задачи для удаления
------------------------------------------------------------
user_states = {}

Клавиатура главного меню (всегда видна снизу)
main_keyboard = ReplyKeyboardMarkup( [["📝 Заметки", "✅ Список дел"]], resize_keyboard=True )

------------------------------------------------------------
Обработчики команд
------------------------------------------------------------
async def start(update: Update, context: ContextTypes.DEFAULT_TYPE): """Точка входа /start. Проверяем, есть ли профиль.""" user_id = update.effective_user.id user = get_user_data(user_id)

if user:
    # Уже зарегистрирован → в главное меню
    user_states[user_id] = "main"
    await update.message.reply_text(
        f"С возвращением, {user['name']}! Вы в главном меню.",
        reply_markup=main_keyboard,
    )
    return ConversationHandler.END  # Завершаем ConversationHandler (если был)
else:
    # Не зарегистрирован → спрашиваем, хочет ли регистрироваться
    await update.message.reply_text(
        "Вы ещё не зарегистрированы. Хотите зарегистрироваться?",
        reply_markup=ReplyKeyboardMarkup(
            [["Да", "Нет"]], one_time_keyboard=True, resize_keyboard=True
        ),
    )
    return AWAIT_REG_CONFIRM
async def reg_confirm(update: Update, context: ContextTypes.DEFAULT_TYPE): """Обрабатываем ответ Да/Нет на предложение регистрации.""" text = update.message.text if text == "Да": await update.message.reply_text("Отлично! Введите ваше имя:") return AWAIT_NAME else: await update.message.reply_text( "Жаль. Если захотите зарегистрироваться, просто введите /start." ) return ConversationHandler.END

async def reg_name(update: Update, context: ContextTypes.DEFAULT_TYPE): """Получаем имя, создаём профиль.""" user_id = update.effective_user.id name = update.message.text user_data = {"name": name, "notes": [], "todos": []} save_user_data(user_id, user_data) user_states[user_id] = "main" await update.message.reply_text( f"Регистрация завершена, {name}! Добро пожаловать.", reply_markup=main_keyboard ) return ConversationHandler.END

async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE): await update.message.reply_text( "Я бот-помощник. Умею хранить заметки и список дел.\n" "Используйте кнопки меню.\n\n" "Команды:\n/start – начало работы\n/help – помощь\n/cancel – отмена текущего действия" )

async def cancel(update: Update, context: ContextTypes.DEFAULT_TYPE): """Сбрасываем любое незавершённое действие и возвращаем в главное меню.""" user_id = update.effective_user.id user_states.pop(user_id, None) # убираем состояние ожидания await update.message.reply_text( "Действие отменено. Вы в главном меню.", reply_markup=main_keyboard ) return ConversationHandler.END

------------------------------------------------------------
Главное меню (кнопки 📝 Заметки / ✅ Список дел)
------------------------------------------------------------
async def main_menu_handler(update: Update, context: ContextTypes.DEFAULT_TYPE): """Нажатие на текстовые кнопки главного меню.""" user_id = update.effective_user.id text = update.message.text user_states[user_id] = "main" # сбрасываем любое предыдущее ожидание

if text == "📝 Заметки":
    await show_notes_menu(update, context)
elif text == "✅ Список дел":
    await show_todos_menu(update, context)
async def show_notes_menu(update: Update, context: ContextTypes.DEFAULT_TYPE): """Отправляем inline-клавиатуру для работы с заметками.""" keyboard = [ [InlineKeyboardButton("➕ Добавить", callback_data="add_note")], [InlineKeyboardButton("📋 Мои заметки", callback_data="view_notes")], [InlineKeyboardButton("🗑 Удалить", callback_data="delete_note")], [InlineKeyboardButton("🔙 Назад", callback_data="back_main")], ] await update.message.reply_text("📝 Меню заметок:", reply_markup=InlineKeyboardMarkup(keyboard))

async def show_todos_menu(update: Update, context: ContextTypes.DEFAULT_TYPE): """Отправляем inline-клавиатуру для работы со списком дел.""" keyboard = [ [InlineKeyboardButton("➕ Добавить задачу", callback_data="add_todo")], [InlineKeyboardButton("📋 Мои задачи", callback_data="view_todos")], [InlineKeyboardButton("🗑 Удалить задачу", callback_data="delete_todo")], [InlineKeyboardButton("🔙 Назад", callback_data="back_main")], ] await update.message.reply_text("✅ Меню задач:", reply_markup=InlineKeyboardMarkup(keyboard))

------------------------------------------------------------
Обработчик нажатий на inline-кнопки (заметки и задачи)
------------------------------------------------------------
async def inline_buttons(update: Update, context: ContextTypes.DEFAULT_TYPE): """Реакция на все callback_data от кнопок.""" query = update.callback_query await query.answer() user_id = update.effective_user.id data = query.data

# --- Навигация ---
if data == "back_main":
    user_states[user_id] = "main"
    await context.bot.send_message(
        chat_id=user_id, text="Главное меню:", reply_markup=main_keyboard
    )
    return

if data == "back_to_notes_menu":
    await query.edit_message_text(
        "📝 Меню заметок:",
        reply_markup=InlineKeyboardMarkup([
            [InlineKeyboardButton("➕ Добавить", callback_data="add_note")],
            [InlineKeyboardButton("📋 Мои заметки", callback_data="view_notes")],
            [InlineKeyboardButton("🗑 Удалить", callback_data="delete_note")],
            [InlineKeyboardButton("🔙 Назад", callback_data="back_main")],
        ]),
    )
    return

if data == "back_to_todos_menu":
    await query.edit_message_text(
        "✅ Меню задач:",
        reply_markup=InlineKeyboardMarkup([
            [InlineKeyboardButton("➕ Добавить задачу", callback_data="add_todo")],
            [InlineKeyboardButton("📋 Мои задачи", callback_data="view_todos")],
            [InlineKeyboardButton("🗑 Удалить задачу", callback_data="delete_todo")],
            [InlineKeyboardButton("🔙 Назад", callback_data="back_main")],
        ]),
    )
    return

# --- Заметки ---
if data == "add_note":
    user_states[user_id] = "awaiting_note"
    await context.bot.send_message(chat_id=user_id, text="Введите текст заметки (или /cancel):")
    return

if data == "view_notes":
    user = get_user_data(user_id)
    if not user or not user.get("notes"):
        await query.edit_message_text("У вас пока нет заметок.")
    else:
        msg = "📌 Ваши заметки:\n" + "\n".join(
            f"{i+1}. {n}" for i, n in enumerate(user["notes"])
        )
        await query.edit_message_text(msg)
    await context.bot.send_message(
        chat_id=user_id,
        text="Вернуться?",
        reply_markup=InlineKeyboardMarkup([
            [InlineKeyboardButton("🔙 Назад", callback_data="back_to_notes_menu")]
        ]),
    )
    return

if data == "delete_note":
    user = get_user_data(user_id)
    if not user or not user.get("notes"):
        await query.edit_message_text("У вас нет заметок для удаления.")
        await context.bot.send_message(
            chat_id=user_id,
            text="Меню:",
            reply_markup=InlineKeyboardMarkup([
                [InlineKeyboardButton("🔙 Назад", callback_data="back_to_notes_menu")]
            ]),
        )
    else:
        user_states[user_id] = "awaiting_delete_note"
        msg = "Ваши заметки:\n" + "\n".join(
            f"{i+1}. {n}" for i, n in enumerate(user["notes"])
        )
        msg += "\n\nВведите номер заметки для удаления:"
        await query.edit_message_text(msg)
    return

# --- Задачи (todos) ---
if data == "add_todo":
    user_states[user_id] = "awaiting_todo"
    await context.bot.send_message(chat_id=user_id, text="Введите задачу (или /cancel):")
    return

if data == "view_todos":
    user = get_user_data(user_id)
    if not user or not user.get("todos"):
        await query.edit_message_text("У вас пока нет задач.")
    else:
        msg = "✅ Ваши задачи:\n" + "\n".join(
            f"{i+1}. {t}" for i, t in enumerate(user["todos"])
        )
        await query.edit_message_text(msg)
    await context.bot.send_message(
        chat_id=user_id,
        text="Вернуться?",
        reply_markup=InlineKeyboardMarkup([
            [InlineKeyboardButton("🔙 Назад", callback_data="back_to_todos_menu")]
        ]),
    )
    return

if data == "delete_todo":
    user = get_user_data(user_id)
    if not user or not user.get("todos"):
        await query.edit_message_text("У вас нет задач для удаления.")
        await context.bot.send_message(
            chat_id=user_id,
            text="Меню:",
            reply_markup=InlineKeyboardMarkup([
                [InlineKeyboardButton("🔙 Назад", callback_data="back_to_todos_menu")]
            ]),
        )
    else:
        user_states[user_id] = "awaiting_delete_todo"
        msg = "Ваши задачи:\n" + "\n".join(
            f"{i+1}. {t}" for i, t in enumerate(user["todos"])
        )
        msg += "\n\nВведите номер задачи для удаления:"
        await query.edit_message_text(msg)
    return
------------------------------------------------------------
Обработчик текстовых сообщений, когда мы чего-то ждём
------------------------------------------------------------
async def handle_user_input(update: Update, context: ContextTypes.DEFAULT_TYPE): """Ловим ответы пользователя в состояниях ожидания.""" user_id = update.effective_user.id state = user_states.get(user_id, "main") text = update.message.text

# ----- Добавление заметки -----
if state == "awaiting_note":
    user = get_user_data(user_id)
    if not user:
        await update.message.reply_text("Ошибка. Введите /start для перезапуска.")
        return
    user["notes"].append(text)
    save_user_data(user_id, user)
    user_states[user_id] = "main"
    await update.message.reply_text(f"✅ Заметка добавлена: {text}")
    await update.message.reply_text(
        "Меню заметок:",
        reply_markup=InlineKeyboardMarkup([
            [InlineKeyboardButton("➕ Добавить", callback_data="add_note")],
            [InlineKeyboardButton("📋 Мои заметки", callback_data="view_notes")],
            [InlineKeyboardButton("🗑 Удалить", callback_data="delete_note")],
            [InlineKeyboardButton("🔙 Назад", callback_data="back_main")],
        ]),
    )
    return

# ----- Удаление заметки -----
if state == "awaiting_delete_note":
    user = get_user_data(user_id)
    if not user:
        await update.message.reply_text("Ошибка. Введите /start.")
        return
    try:
        idx = int(text) - 1
        if 0 <= idx < len(user["notes"]):
            removed = user["notes"].pop(idx)
            save_user_data(user_id, user)
            user_states[user_id] = "main"
            await update.message.reply_text(f"🗑 Заметка удалена: {removed}")
        else:
            await update.message.reply_text("Нет такого номера. Попробуйте ещё раз.")
            return
    except ValueError:
        await update.message.reply_text("Введите число — номер заметки.")
        return
    await update.message.reply_text(
        "Меню заметок:",
        reply_markup=InlineKeyboardMarkup([
            [InlineKeyboardButton("➕ Добавить", callback_data="add_note")],
            [InlineKeyboardButton("📋 Мои заметки", callback_data="view_notes")],
            [InlineKeyboardButton("🗑 Удалить", callback_data="delete_note")],
            [InlineKeyboardButton("🔙 Назад", callback_data="back_main")],
        ]),
    )
    return

# ----- Добавление задачи -----
if state == "awaiting_todo":
    user = get_user_data(user_id)
    if not user:
        await update.message.reply_text("Ошибка. Введите /start.")
        return
    user["todos"].append(text)
    save_user_data(user_id, user)
    user_states[user_id] = "main"
    await update.message.reply_text(f"✅ Задача добавлена: {text}")
    await update.message.reply_text(
        "Меню задач:",
        reply_markup=InlineKeyboardMarkup([
            [InlineKeyboardButton("➕ Добавить задачу", callback_data="add_todo")],
            [InlineKeyboardButton("📋 Мои задачи", callback_data="view_todos")],
            [InlineKeyboardButton("🗑 Удалить задачу", callback_data="delete_todo")],
            [InlineKeyboardButton("🔙 Назад", callback_data="back_main")],
        ]),
    )
    return

# ----- Удаление задачи -----
if state == "awaiting_delete_todo":
    user = get_user_data(user_id)
    if not user:
        await update.message.reply_text("Ошибка. Введите /start.")
        return
    try:
        idx = int(text) - 1
        if 0 <= idx < len(user["todos"]):
            removed = user["todos"].pop(idx)
            save_user_data(user_id, user)
            user_states[user_id] = "main"
            await update.message.reply_text(f"🗑 Задача удалена: {removed}")
        else:
            await update.message.reply_text("Нет такого номера. Попробуйте ещё раз.")
            return
    except ValueError:
        await update.message.reply_text("Введите число — номер задачи.")
        return
    await update.message.reply_text(
        "Меню задач:",
        reply_markup=InlineKeyboardMarkup([
            [InlineKeyboardButton("➕ Добавить задачу", callback_data="add_todo")],
            [InlineKeyboardButton("📋 Мои задачи", callback_data="view_todos")],
            [InlineKeyboardButton("🗑 Удалить задачу", callback_data="delete_todo")],
            [InlineKeyboardButton("🔙 Назад", callback_data="back_main")],
        ]),
    )
    return

# Если состояние не требует специальной обработки — просто показываем главное меню
await update.message.reply_text("Используйте кнопки меню.", reply_markup=main_keyboard)
------------------------------------------------------------
Точка входа
------------------------------------------------------------
def main(): TOKEN = "ВАШ ТОКЕН" # <-- замените на токен от BotFather

app = Application.builder().token(TOKEN).build()

# ConversationHandler только для регистрации
reg_conv_handler = ConversationHandler(
    entry_points=[CommandHandler("start", start)],
    states={
        AWAIT_REG_CONFIRM: [MessageHandler(filters.Regex("^(Да|Нет)$"), reg_confirm)],
        AWAIT_NAME: [MessageHandler(filters.TEXT & ~filters.COMMAND, reg_name)],
    },
    fallbacks=[CommandHandler("cancel", cancel)],
)
app.add_handler(reg_conv_handler)

# Остальные обработчики
app.add_handler(MessageHandler(filters.Regex("^(📝 Заметки|✅ Список дел)$"), main_menu_handler))
app.add_handler(CallbackQueryHandler(inline_buttons))
app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_user_input))
app.add_handler(CommandHandler("help", help_command))
app.add_handler(CommandHandler("cancel", cancel))

print("Бот запущен...")
app.run_polling()
if name == "main": main()