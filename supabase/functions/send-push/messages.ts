// Push texts for system notifications, in the recipient's language. The
// app's inbox renders the same types from type_key + data.

type Data = Record<string, unknown>;
type Text = { title: string; body: string };
type Lang = "ar" | "en";

const t = (lang: Lang, ar: string, en: string) => (lang === "ar" ? ar : en);

export function render(type: string, data: Data, lang: Lang, names: { trainee?: string }): Text | null {
  switch (type) {
    case "application_result":
      return data.status === "approved"
        ? { title: t(lang, "تمت الموافقة على حسابك 🎉", "Your account is approved 🎉"),
            body: t(lang, "افتح التطبيق وابدأ.", "Open the app to get started.") }
        : { title: t(lang, "طلبك متقبلش", "Your application wasn't approved"),
            body: t(lang, "تقدر تعدل إجاباتك وتقدم تاني.", "You can update your answers and apply again.") };
    case "plan_ready":
      return {
        title: t(lang, "خطتك جاهزة", "Your plan is ready"),
        body: data.kind === "nutrition"
          ? t(lang, "مدربك جهز خطة الأكل بتاعتك.", "Your coach updated your nutrition plan.")
          : t(lang, "مدربك جهز خطة التمرين بتاعتك.", "Your coach updated your workout plan."),
      };
    case "milestone_due":
      return { title: t(lang, "موعد المتابعة النهارده", "Check-in due today"),
               body: t(lang, "ارفع وزنك وصورك من التطبيق.", "Add your weight and photos in the app.") };
    case "milestone_uploaded":
      return { title: t(lang, "متابعة جديدة", "New check-in"),
               body: t(lang, `${names.trainee ?? "متدرب"} رفع متابعة جديدة.`, `${names.trainee ?? "A trainee"} uploaded a check-in.`) };
    case "trainee_assigned":
      return { title: t(lang, "متدرب جديد", "New trainee"),
               body: t(lang, `${names.trainee ?? "متدرب جديد"} اتضاف ليك.`, `${names.trainee ?? "A new trainee"} was assigned to you.`) };
    case "chat_message":
      return { title: String(data.sender_name ?? t(lang, "رسالة جديدة", "New message")), body: String(data.preview ?? "") };
    case "subscription_recorded":
      return { title: t(lang, "تم استلام الدفع", "Payment received"),
               body: t(lang, `استلمنا ${data.amount_egp} جنيه لمدة ${data.days} يوم.`,
                             `We received EGP ${data.amount_egp} for ${data.days} days.`) };
    case "subscription_ending":
      return data.trainee_name
        ? { title: t(lang, "اشتراك قرب يخلص", "Subscription ending"),
            body: t(lang, `اشتراك ${data.trainee_name} هيخلص بعد ${data.days_left} يوم.`,
                          `${data.trainee_name}'s subscription ends in ${data.days_left} days.`) }
        : { title: t(lang, "اشتراكك قرب يخلص", "Your subscription is ending"),
            body: t(lang, `فاضل ${data.days_left} يوم.`, `${data.days_left} days left.`) };
    case "no_data_today":
      return { title: t(lang, "لسه مسجلتش حاجة النهارده", "Nothing logged today"),
               body: t(lang, "سجل تمرينك ووجباتك عشان تحافظ على الاستمرارية.", "Log your workout and meals to keep your streak.") };
    default:
      return null;
  }
}
