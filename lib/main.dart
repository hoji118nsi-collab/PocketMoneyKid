import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PocketMoneyKidApp());
}

class PocketMoneyKidApp extends StatelessWidget {
  const PocketMoneyKidApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'صندوقِ جیبی',
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: PocketHome(),
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}

class PocketHome extends StatefulWidget {
  const PocketHome({super.key});

  @override
  State<PocketHome> createState() => _PocketHomeState();
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
    return nf.format(v.roundToDouble() == v ? v.toInt() : v);
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
      expenses.clear();
      monthlyAllowance = 0;
      rewardThisMonth = 0;
    });
    _saveAll();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('پایان ماه ثبت شد. مبلغ برای سرمایه‌گذاری اضافه شد: ${fmt(toInvest)}')));
  }

  void _buyFromWishlist(WishlistItem item) {
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
}
