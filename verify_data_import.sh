#!/bin/bash
# Verify data was imported after granting permissions

DB_PATH="/Users/andrewsoulier/My_CRM Project/my_crm_2.db"
LOG_PATH=~/Library/Application\ Support/My_CRM/Logs/crm_debug.log

echo "🔍 Checking if data was imported..."
echo ""

echo "📊 Database Table Counts:"
echo "========================"
sqlite3 "$DB_PATH" "SELECT 'Contacts: ' || COUNT(*) FROM contacts;"
sqlite3 "$DB_PATH" "SELECT 'Groups: ' || COUNT(*) FROM groups;"
sqlite3 "$DB_PATH" "SELECT 'Messages: ' || COUNT(*) FROM messages;"
echo ""

echo "📝 Latest Import Logs:"
echo "===================="
echo ""
echo "ContactsImporter:"
grep "ContactsImporter.run()" "$LOG_PATH" | tail -3
echo ""
echo "MessagesImporter:"  
grep "MessagesImporter.run()" "$LOG_PATH" | tail -3
echo ""

# Check for success indicators
CONTACT_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM contacts;")
MESSAGE_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM messages;")

if [ "$CONTACT_COUNT" -gt 0 ]; then
    echo "✅ Contacts imported successfully! ($CONTACT_COUNT contacts)"
else
    echo "⚠️  No contacts imported yet - check Contacts permission"
fi

if [ "$MESSAGE_COUNT" -gt 0 ]; then
    echo "✅ Messages imported successfully! ($MESSAGE_COUNT messages)"
else
    echo "⚠️  No messages imported yet - check Full Disk Access permission"
fi

