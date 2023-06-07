#include "zlineedit.h"
#include "znumslider.h"
#include "style/zenostyle.h"
#include <QSvgRenderer>
#include <zenoedit/zenoapplication.h>
#include <zenoedit/zenomainwindow.h>
#include <zenoedit/timeline/ztimeline.h>
#include "./dialog/curvemap/zcurvemapeditor.h"

const char *g_setKey = "setKey";
const char *g_keyFrame = "keyFrame";

ZLineEdit::ZLineEdit(QWidget* parent)
    : QLineEdit(parent)
    , m_pSlider(nullptr)
    , m_bShowingSlider(false)
    , m_bHasRightBtn(false)
    , m_pButton(nullptr)
    , m_bIconHover(false)

{
    init();
}

ZLineEdit::ZLineEdit(const QString& text, QWidget* parent)
    : QLineEdit(text, parent)
    , m_pSlider(nullptr)
    , m_bShowingSlider(false)
    , m_bHasRightBtn(false)
    , m_pButton(nullptr)
    , m_bIconHover(false)
{
    init();
}

void ZLineEdit::init()
{
    connect(this, SIGNAL(editingFinished()), this, SIGNAL(textEditFinished()));
}

void ZLineEdit::setShowingSlider(bool bShow)
{
    m_bShowingSlider = bShow;
}

void ZLineEdit::setIcons(const QString& icNormal, const QString& icHover)
{
    m_iconNormal = icNormal;
    m_iconHover = icHover;
    m_pButton = new QPushButton(this);
    m_pButton->setFixedSize(ZenoStyle::dpiScaled(20), ZenoStyle::dpiScaled(20));
    m_pButton->installEventFilter(this);
    QHBoxLayout *btnLayout = new QHBoxLayout(this);
    btnLayout->addStretch();
    btnLayout->addWidget(m_pButton);
    btnLayout->setAlignment(Qt::AlignRight);
    btnLayout->setContentsMargins(0, 0, 0, 0);
    connect(m_pButton, SIGNAL(clicked(bool)), this, SIGNAL(btnClicked()));
}

void ZLineEdit::setNumSlider(const QVector<qreal>& steps)
{
    if (steps.isEmpty())
        return;

    m_steps = steps;
    m_pSlider = new ZNumSlider(m_steps, this);
    m_pSlider->setWindowFlags(Qt::Window | Qt::FramelessWindowHint);
    m_pSlider->hide();

    connect(m_pSlider, &ZNumSlider::numSlided, this, [=](qreal val) {
        bool bOk = false;
        qreal num = this->text().toFloat(&bOk);
        if (bOk)
        {
            num = num + val;
            QString newText = QString::number(num);
            setText(newText);
        }
    });
    connect(m_pSlider, &ZNumSlider::slideFinished, this, [=]() {
        setShowingSlider(false);
        emit editingFinished();
    });
}

void ZLineEdit::mouseReleaseEvent(QMouseEvent* event)
{
    QLineEdit::mouseReleaseEvent(event);
}

void ZLineEdit::popupSlider()
{
    if (!m_pSlider)
        return;

    QSize sz = m_pSlider->size();
    QRect rc = QApplication::desktop()->screenGeometry();
    static const int _yOffset = ZenoStyle::dpiScaled(20);

    QPoint pos = this->cursor().pos();
    pos.setY(std::min(pos.y(), rc.bottom() - sz.height() / 2 - _yOffset));
    pos -= QPoint(0, sz.height() / 2);

    m_pSlider->move(pos);
    m_pSlider->show();
    m_pSlider->activateWindow();
    m_pSlider->setFocus();
    m_pSlider->raise();
    setShowingSlider(true);
}

bool ZLineEdit::event(QEvent* event)
{
    if (event->type() == QEvent::KeyPress)
    {
        QKeyEvent* k = (QKeyEvent*)event;
        if (m_pSlider && k->key() == Qt::Key_Shift)
        {
            popupSlider();
            k->accept();
            return true;
        }
    }
    return QLineEdit::event(event);
}

void ZLineEdit::keyPressEvent(QKeyEvent* event)
{
    QLineEdit::keyPressEvent(event);
}

void ZLineEdit::keyReleaseEvent(QKeyEvent* event)
{
    int k = event->key();
    if (k == Qt::Key_Shift && m_pSlider)
    {
        m_pSlider->hide();
        setShowingSlider(false);
    }
    QLineEdit::keyReleaseEvent(event);
}

void ZLineEdit::paintEvent(QPaintEvent* event)
{
    QLineEdit::paintEvent(event);
    if (m_bShowingSlider)
    {
        QPainter p(this);
        QRect rc = rect();
        p.setPen(QColor("#4B9EF4"));
        p.setRenderHint(QPainter::Antialiasing, false);
        p.drawRect(rc.adjusted(0,0,-1,-1));
    }
}

bool ZLineEdit::eventFilter(QObject *obj, QEvent *event) {
    if (obj == m_pButton) {
        if (event->type() == QEvent::Paint) {
            QSvgRenderer svgRender;
            QPainter painter(m_pButton);
            QRect rc = m_pButton->rect();
            if (m_bIconHover)
                svgRender.load(m_iconHover);
            else
                svgRender.load(m_iconNormal);
            svgRender.render(&painter, rc);
            return true;
        } else if (event->type() == QEvent::HoverEnter) {
            setCursor(QCursor(Qt::ArrowCursor));
            m_bIconHover = true;
        } else if (event->type() == QEvent::HoverLeave) {
            setCursor(QCursor(Qt::IBeamCursor));
            m_bIconHover = false;
        }
    }
    return QLineEdit::eventFilter(obj, event);
}

//FLOAT LINEEDIT
ZFloatLineEdit::ZFloatLineEdit(QWidget *parent):
    ZLineEdit(parent)
{
    setProperty(g_setKey, "null");
}
ZFloatLineEdit::ZFloatLineEdit(const QString &text, QWidget *parent) : 
    ZLineEdit(text, parent)
{
    setProperty(g_setKey, "null");
}

void ZFloatLineEdit::updateCurveData() 
{
    CURVE_DATA val;
    if (!getKeyFrame(val)) {
        return;
    }
    if (ZTimeline *timeline = getTimeline()) {
        float x = timeline->value();
        float y = text().toFloat();
        if (val.visible) {
            bool bUpdate = curve_util::updateCurve(QPoint(x, y), val);
            if (bUpdate)
                setProperty(g_keyFrame, QVariant::fromValue(val));
        } else {
            val.points.begin()->point = QPointF(x, y);
            setProperty(g_keyFrame, QVariant::fromValue(val));
        }
    }
}

bool ZFloatLineEdit::event(QEvent *event) 
{
    CURVE_DATA curve;
    {
        ZTimeline *timeline = getTimeline();
        ZASSERT_EXIT(timeline, false);
        if (event->type() == QEvent::DynamicPropertyChange) {
            QDynamicPropertyChangeEvent *evt = static_cast<QDynamicPropertyChangeEvent*>(event); 
            if (evt->propertyName() == g_keyFrame) {
                updateBackgroundProp(timeline->value());
                if (getKeyFrame(curve)) {
                    connect(timeline, &ZTimeline::sliderValueChanged, this, &ZFloatLineEdit::updateBackgroundProp, Qt::UniqueConnection);
                    connect( zenoApp->getMainWindow(), &ZenoMainWindow::visFrameUpdated, this, &ZFloatLineEdit::onUpdate, Qt::UniqueConnection);
                } else {
                    disconnect(timeline, &ZTimeline::sliderValueChanged, this, &ZFloatLineEdit::updateBackgroundProp);
                    disconnect( zenoApp->getMainWindow(), &ZenoMainWindow::visFrameUpdated, this, &ZFloatLineEdit::onUpdate);
                }
            }
        } 
        else if (event->type() == QEvent::FocusOut) {
            updateCurveData();
        }
    }
    ZLineEdit::event(event);
}

void ZFloatLineEdit::updateBackgroundProp(int frame) 
{
    CURVE_DATA data;
    if (getKeyFrame(data)) {
        QString text = QString::number(data.eval(frame));
        setText(text);
        if (isSetKeyFrame()) {
            setProperty(g_setKey, "true");
        } else if (data.visible) {
            setProperty(g_setKey, "false");
        } else {
            setProperty(g_setKey, "null");
        }
    } else {
        setProperty(g_setKey, "null");
    }
    this->style()->unpolish(this);
    this->style()->polish(this);
    update();
}
void ZFloatLineEdit::onUpdate(bool gl, int frame) 
{
    updateBackgroundProp(frame);
}
ZTimeline *ZFloatLineEdit::getTimeline() 
{
    ZenoMainWindow *mainWin = zenoApp->getMainWindow();
    ZASSERT_EXIT(mainWin, nullptr);
    ZTimeline *timeline = mainWin->timeline();
    ZASSERT_EXIT(timeline, nullptr);
    return timeline;
}
bool ZFloatLineEdit::isSetKeyFrame() 
{
    if (ZTimeline *timeline = getTimeline()) {
        CURVE_DATA data;
        if (getKeyFrame(data)) {
            int x = timeline->value();
            for (auto p : data.points) {
                int px = p.point.x();
                if ((px == x) && data.visible) {
                    return true;
                }
            }
        }
    }
    return false;
}

bool ZFloatLineEdit::getKeyFrame(CURVE_DATA &curve) 
{
    bool res = property(g_keyFrame).canConvert<CURVE_DATA>();
    if (res)
        curve = property(g_keyFrame).value<CURVE_DATA>();
    return res;
}
