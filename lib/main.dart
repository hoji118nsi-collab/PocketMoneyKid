import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(PocketMoneyKidApp());
}

class PocketMoneyKidApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'صندوقِ جیبی',
      home: Directionality(textDirection: TextDirection.rtl, child: PocketHome()),
      debugShowCheckedModeBanner: false,
    );
  }
}

class PocketHome extends StatefulWidget {
  @override
  _PocketHomeState createState() => _PocketHomeState();
}

class _PocketHomeState extends State<PocketHome> {
  double monthlyAllowance = 0;
  List<Expense> expenses = [];
  List<WishlistItem> wishlist = [];
  double investment = 0;
  double debt = 0;
  double rewardThisMonth = 0;

  final _allowanceController = TextEditingController();
  final _expenseTitleController = TextEditingController();
  final _expenseAmountController = TextEditingController();
  final _wishTitleController = TextEditingController();
  final _wishPriceController = TextEditingController();
  final _debtController = TextEditingController();
  final _spendController = TextEditingController();

  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  String fmt(double v) {
    final nf = NumberFormat('#,###', 'fa');
    if (v == v.roundToDouble()) {
      return nf.format(v.toInt());
    }
    return nf.format(v);
  }

  Future<void> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      monthlyAllowance = prefs.getDouble('monthlyAllowance') ?? 0;
      investment = prefs.getDouble('investment') ?? 0;
      debt = prefs.getDouble('debt') ?? 0;
      rewardThisMonth = prefs.getDouble('rewardThisMonth') ?? 0;

      final expJson = prefs.getString('expenses') ?? '[]';
      final wishJson = prefs.getString('wishlist') ?? '[]';

      expenses = (jsonDecode(expJson) as List).map((e) => Expense.fromJson(e)).toList();
      wishlist = (jsonDecode(wishJson) as List).map((w) => WishlistItem.fromJson(w)).toList();

      loading = false;
    });
  }

  Future<void> _saveAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('monthlyAllowance', monthlyAllowance);
    await prefs.setDouble('investment', investment);
    await prefs.setDouble('debt', debt);
    await prefs.setDouble('rewardThisMonth', rewardThisMonth);
    await prefs.setString('expenses', jsonEncode(expenses.map((e) => e.toJson()).toList()));
    await prefs.setString('wishlist', jsonEncode(wishlist.map((w) => w.toJson()).toList()));
  }

  double get totalExpenses => expenses.fold(0.0, (p, e) => p + e.amount);
  double get currentSaving => (monthlyAllowance - totalExpenses).clamp(0.0, double.infinity);

  void _setAllowance() {
    final v = double.tryParse(_allowanceController.text.replaceAll(',', '')) ?? 0;
    setState(() {
      monthlyAllowance = v;
    });
    // At start of month, if there's debt, try to deduct automatically from allowance up to debt
    if (debt > 0 && monthlyAllowance > 0) {
      final deduct = monthlyAllowance <= debt ? monthlyAllowance : debt;
      debt -= deduct;
      monthlyAllowance -= deduct;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('مقداری از پول ماهیانه برای پرداخت بدهی کسر شد: ${fmt(deduct)}')));
    }
    _saveAll();
    Navigator.of(context).pop();
  }

  void _addExpense() {
    final title = _expenseTitleController.text.trim();
    final amount = double.tryParse(_expenseAmountController.text.replaceAll(',', '')) ?? 0;
    if (title.isEmpty || amount <= 0) return;
    setState(() {
      expenses.add(Expense(title: title, amount: amount));
      _expenseTitleController.clear();
      _expenseAmountController.clear();
    });
    _saveAll();
    Navigator.of(context).pop();
  }

  void _addWishlist() {
    final title = _wishTitleController.text.trim();
    final price = double.tryParse(_wishPriceController.text.replaceAll(',', '')) ?? 0;
    if (title.isEmpty || price <= 0) return;
    setState(() {
      wishlist.add(WishlistItem(title: title, price: price));
      _wishTitleController.clear();
      _wishPriceController.clear();
    });
    _saveAll();
    Navigator.of(context).pop();
  }

  void _addDebt() {
    final amt = double.tryParse(_debtController.text.replaceAll(',', '')) ?? 0;
    if (amt == 0) return;
    setState(() {
      debt += amt;
      _debtController.clear();
    });
    _saveAll();
    Navigator.of(context).pop();
  }

  // End of month processing: optionally spend part on wishlist or arbitrary amount.
  // reward = remaining saving; parent matches it, so investment increases by remaining + reward.
  void _endOfMonthProcess({double spendFromSaving = 0, WishlistItem? boughtItem}) {
    final save = currentSaving;
    final spend = spendFromSaving.clamp(0, save);
    final remaining = (save - spend).clamp(0, double.infinity);

    if (boughtItem != null) {
      boughtItem.purchased = true;
    }

    rewardThisMonth = remaining;
    final toInvest = remaining + rewardThisMonth;
    setState(() {
      investment += toInvest;
      // clear month
      expenses.clear();
      monthlyAllowance = 0;
      rewardThisMonth = 0;
    });
    _saveAll();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('پایان ماه ثبت شد. مبلغ برای سرمایه‌گذاری اضافه شد: ${fmt(toInvest)}')));
  }

  void _buyFromWishlist(WishlistItem item) {
    // show dialog to choose how much to spend (max item.price and max currentSaving)
    _spendController.text = item.price.toInt().toString();
    showDialog(context: context, builder: (_) => AlertDialog(
      title: Text('خرید ${item.title}'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('قیمت: ${fmt(item.price)}'),
        SizedBox(height: 8),
        Text('پس‌انداز فعلی: ${fmt(currentSaving)}'),
        SizedBox(height: 8),
        TextField(controller: _spendController, keyboardType: TextInputType.number, decoration: InputDecoration(hintText: 'مبلغ برای خرج کردن')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('لغو')),
        ElevatedButton(onPressed: () {
          final spend = double.tryParse(_spendController.text.replaceAll(',', '')) ?? 0;
          if (spend > currentSaving) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('مقدار بیشتر از پس‌انداز فعلی است')));
            return;
          }
          setState(() {
            // deduct by treating as an expense this month before end-of-month processing
            expenses.add(Expense(title: 'خرید: ${item.title}', amount: spend));
          });
          Navigator.of(context).pop();
        }, child: Text('استفاده از پس‌انداز')),
      ],
    ));
  }

  void _openWishlist() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => Directionality(textDirection: TextDirection.rtl, child: WishlistPage(
      wishlist: wishlist,
      onAdd: (t,p) { setState(() { wishlist.add(WishlistItem(title: t, price: p)); }); _saveAll(); },
      onBuy: (item) { _buyFromWishlist(item); },
    ))));
  }

  void _showEndOfMonthDialog() {
    _spendController.clear();
    showDialog(context: context, builder: (_) => AlertDialog(
      title: Text('پایان ماه - محاسبه پس‌انداز و جایزه'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('پس‌انداز محاسبه‌شده: ${fmt(currentSaving)}'),
        SizedBox(height: 8),
        Text('می‌خواهی چقدر از پس‌انداز را برای خرید استفاده کنی؟ (اگر مبلغی وارد نکنی، کل پس‌انداز سرمایه‌گذاری می‌شود)'), 
        SizedBox(height: 8),
        TextField(controller: _spendController, keyboardType: TextInputType.number, decoration: InputDecoration(hintText: 'مقدار برای خرج (تومان)')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('انصراف')),
        ElevatedButton(onPressed: () {
          final spend = double.tryParse(_spendController.text.replaceAll(',', '')) ?? 0;
          _endOfMonthProcess(spendFromSaving: spend);
          Navigator.of(context).pop();
        }, child: Text('ثبت و محاسبه')),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: Text('صندوقِ جیبی - داشبورد')),
      body: Padding(padding: const EdgeInsets.all(12), child: SingleChildScrollView(child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('موجودی سرمایه‌گذاری: ${fmt(investment)}', style: TextStyle(fontSize: 18)),
            SizedBox(height: 6),
            Text('میزان بدهی به پدر: ${fmt(debt)}'),
            SizedBox(height: 6),
            Text('پول ماهانه فعلی: ${fmt(monthlyAllowance)}'),
            SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              ElevatedButton.icon(onPressed: () => _showSetAllowanceDialog(), icon: Icon(Icons.edit), label: Text('ثبت پول ماهانه')),
              ElevatedButton.icon(onPressed: () => _openWishlist(), icon: Icon(Icons.list_alt), label: Text('ویش‌لیست')),
              ElevatedButton.icon(onPressed: () => _showAddExpenseDialog(), icon: Icon(Icons.add_shopping_cart), label: Text('ثبت هزینه')),
              ElevatedButton.icon(onPressed: () => _showEndOfMonthDialog(), icon: Icon(Icons.date_range), label: Text('پایان ماه')),
            ])
          ]))),
          SizedBox(height: 12),
          Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('گزارش سریع', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 6),
            Text('جمع هزینه‌ها: ${fmt(totalExpenses)}'),
            Text('پس‌انداز فعلی: ${fmt(currentSaving)}'),
            Text('تعداد اهداف ویش‌لیست: ${wishlist.length}'),
          ]))),
          SizedBox(height: 12),
          Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('افزودن قرض به پدر', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: _debtController, keyboardType: TextInputType.number, decoration: InputDecoration(hintText: 'مقدار قرض'))),
              SizedBox(width: 8),
              ElevatedButton(onPressed: _addDebt, child: Text('ثبت')),
            ])
          ]))),
          SizedBox(height: 12),
          Text('لیست هزینه‌ها', style: TextStyle(fontWeight: FontWeight.bold)),
          ...expenses.map((e) => ListTile(title: Text(e.title), trailing: Text(fmt(e.amount)))).toList(),
        ],
      ))),
    );
  }

  void _showSetAllowanceDialog() {
    _allowanceController.text = monthlyAllowance.toInt().toString();
    showDialog(context: context, builder: (_) => AlertDialog(
      title: Text('ثبت پول ماهانه'),
      content: TextField(controller: _allowanceController, keyboardType: TextInputType.number, decoration: InputDecoration(hintText: 'مبلغ را وارد کنید')),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('لغو')),
        ElevatedButton(onPressed: _setAllowance, child: Text('ثبت')),
      ],
    ));
  }

  void _showAddExpenseDialog() {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: Text('ثبت هزینه'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: _expenseTitleController, decoration: InputDecoration(hintText: 'عنوان')),
        SizedBox(height: 8),
        TextField(controller: _expenseAmountController, keyboardType: TextInputType.number, decoration: InputDecoration(hintText: 'مبلغ')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('لغو')),
        ElevatedButton(onPressed: _addExpense, child: Text('افزودن')),
      ],
    ));
  }
}

class Expense {
  String title;
  double amount;
  Expense({required this.title, required this.amount});
  Map<String, dynamic> toJson() => {'title': title, 'amount': amount};
  static Expense fromJson(Map<String, dynamic> j) => Expense(title: j['title'] ?? '', amount: (j['amount'] as num).toDouble());
}

class WishlistItem {
  String title;
  double price;
  bool purchased;
  WishlistItem({required this.title, required this.price, this.purchased = false});
  Map<String, dynamic> toJson() => {'title': title, 'price': price, 'purchased': purchased};
  static WishlistItem fromJson(Map<String, dynamic> j) => WishlistItem(title: j['title'] ?? '', price: (j['price'] as num).toDouble(), purchased: j['purchased'] ?? false);
}

class WishlistPage extends StatefulWidget {
  final List<WishlistItem> wishlist;
  final void Function(String title, double price) onAdd;
  final void Function(WishlistItem item) onBuy;
  WishlistPage({required this.wishlist, required this.onAdd, required this.onBuy});

  @override
  _WishlistPageState createState() => _WishlistPageState();
}

class _WishlistPageState extends State<WishlistPage> {
  final _titleC = TextEditingController();
  final _priceC = TextEditingController();
  String fmtNum(double v) {
    final nf = NumberFormat('#,###', 'fa');
    if (v == v.roundToDouble()) return nf.format(v.toInt());
    return nf.format(v);
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('ویش‌لیست')),
      body: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
        Expanded(child: ListView.builder(itemCount: widget.wishlist.length, itemBuilder: (_, i) {
          final it = widget.wishlist[i];
          return Card(child: ListTile(
            title: Text(it.title),
            subtitle: Text('قیمت: ${fmtNum(it.price)}'),
            trailing: it.purchased ? Icon(Icons.check, color: Colors.green) : ElevatedButton(child: Text('خرید'), onPressed: () => widget.onBuy(it)),
          ));
        })),
        Divider(),
        Text('افزودن هدف جدید', style: TextStyle(fontWeight: FontWeight.bold)),
        TextField(controller: _titleC, decoration: InputDecoration(hintText: 'نام کالا')),
        SizedBox(height: 8),
        TextField(controller: _priceC, keyboardType: TextInputType.number, decoration: InputDecoration(hintText: 'قیمت')),
        SizedBox(height: 8),
        ElevatedButton(onPressed: () {
          final t = _titleC.text.trim();
          final p = double.tryParse(_priceC.text.replaceAll(',', '')) ?? 0;
          if (t.isNotEmpty && p > 0) {
            widget.onAdd(t, p);
            _titleC.clear();
            _priceC.clear();
          }
        }, child: Text('افزودن'))
      ])),
    );
  }
}