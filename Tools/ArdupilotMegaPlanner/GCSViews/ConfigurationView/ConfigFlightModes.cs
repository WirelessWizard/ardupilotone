﻿using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Drawing;
using System.Data;
using System.Linq;
using System.Text;
using System.Windows.Forms;
using ArdupilotMega.Controls.BackstageView;

namespace ArdupilotMega.GCSViews.ConfigurationView
{
    public partial class ConfigFlightModes : BackStageViewContentPanel
    {
        Timer timer = new Timer();

        public ConfigFlightModes()
        {
            InitializeComponent();

            timer.Tick += new EventHandler(timer_Tick);

            timer.Enabled = true;
            timer.Interval = 100;
            timer.Start();
        }

        void timer_Tick(object sender, EventArgs e)
        {
            try
            {
                MainV2.cs.UpdateCurrentSettings(currentStateBindingSource);
            }
            catch { }

            float pwm = 0;

            if (MainV2.cs.firmware == MainV2.Firmwares.ArduPlane) // APM 
            {
                if (MainV2.comPort.param.ContainsKey("FLTMODE_CH"))
                {
                    switch ((int)(float)MainV2.comPort.param["FLTMODE_CH"])
                    {
                        case 5:
                            pwm = MainV2.cs.ch5in;
                            break;
                        case 6:
                            pwm = MainV2.cs.ch6in;
                            break;
                        case 7:
                            pwm = MainV2.cs.ch7in;
                            break;
                        case 8:
                            pwm = MainV2.cs.ch8in;
                            break;
                        default:

                            break;
                    }

                    LBL_flightmodepwm.Text = MainV2.comPort.param["FLTMODE_CH"].ToString() + ": " + pwm.ToString();
                }
            }

            if (MainV2.cs.firmware == MainV2.Firmwares.ArduCopter2) // ac2
            {
                pwm = MainV2.cs.ch5in;
                LBL_flightmodepwm.Text = "5: " + MainV2.cs.ch5in.ToString();
            }

            Control[] fmodelist = new Control[] { CMB_fmode1, CMB_fmode2, CMB_fmode3, CMB_fmode4, CMB_fmode5, CMB_fmode6 };

            foreach (Control ctl in fmodelist)
            {
                ctl.BackColor = Color.FromArgb(0x43, 0x44, 0x45);
            }

            byte no = readSwitch(pwm);

            fmodelist[no].BackColor = Color.Green;
        }

        // from arducopter code
        byte readSwitch(float inpwm)
        {
            int pulsewidth = (int)inpwm;			// default for Arducopter

            if (pulsewidth > 1230 && pulsewidth <= 1360) return 1;
            if (pulsewidth > 1360 && pulsewidth <= 1490) return 2;
            if (pulsewidth > 1490 && pulsewidth <= 1620) return 3;
            if (pulsewidth > 1620 && pulsewidth <= 1749) return 4;	// Software Manual
            if (pulsewidth >= 1750) return 5;	// Hardware Manual
            return 0;
        }

        private void BUT_SaveModes_Click(object sender, EventArgs e)
        {
            try
            {
                if (MainV2.cs.firmware == MainV2.Firmwares.ArduPlane) // APM
                {
                    MainV2.comPort.setParam("FLTMODE1", (float)(int)Enum.Parse(typeof(Common.apmmodes), CMB_fmode1.Text));
                    MainV2.comPort.setParam("FLTMODE2", (float)(int)Enum.Parse(typeof(Common.apmmodes), CMB_fmode2.Text));
                    MainV2.comPort.setParam("FLTMODE3", (float)(int)Enum.Parse(typeof(Common.apmmodes), CMB_fmode3.Text));
                    MainV2.comPort.setParam("FLTMODE4", (float)(int)Enum.Parse(typeof(Common.apmmodes), CMB_fmode4.Text));
                    MainV2.comPort.setParam("FLTMODE5", (float)(int)Enum.Parse(typeof(Common.apmmodes), CMB_fmode5.Text));
                    MainV2.comPort.setParam("FLTMODE6", (float)(int)Enum.Parse(typeof(Common.apmmodes), CMB_fmode6.Text));
                }
                if (MainV2.cs.firmware == MainV2.Firmwares.ArduCopter2) // ac2
                {
                    MainV2.comPort.setParam("FLTMODE1", (float)(int)Enum.Parse(typeof(Common.ac2modes), CMB_fmode1.Text));
                    MainV2.comPort.setParam("FLTMODE2", (float)(int)Enum.Parse(typeof(Common.ac2modes), CMB_fmode2.Text));
                    MainV2.comPort.setParam("FLTMODE3", (float)(int)Enum.Parse(typeof(Common.ac2modes), CMB_fmode3.Text));
                    MainV2.comPort.setParam("FLTMODE4", (float)(int)Enum.Parse(typeof(Common.ac2modes), CMB_fmode4.Text));
                    MainV2.comPort.setParam("FLTMODE5", (float)(int)Enum.Parse(typeof(Common.ac2modes), CMB_fmode5.Text));
                    MainV2.comPort.setParam("FLTMODE6", (float)(int)Enum.Parse(typeof(Common.ac2modes), CMB_fmode6.Text));

                    float value = (float)(CB_simple1.Checked ? (int)SimpleMode.Simple1 : 0) + (CB_simple2.Checked ? (int)SimpleMode.Simple2 : 0) + (CB_simple3.Checked ? (int)SimpleMode.Simple3 : 0)
                        + (CB_simple4.Checked ? (int)SimpleMode.Simple4 : 0) + (CB_simple5.Checked ? (int)SimpleMode.Simple5 : 0) + (CB_simple6.Checked ? (int)SimpleMode.Simple6 : 0);
                    if (MainV2.comPort.param.ContainsKey("SIMPLE"))
                        MainV2.comPort.setParam("SIMPLE", value);
                }
            }
            catch { CustomMessageBox.Show("Failed to set Flight modes"); }
            BUT_SaveModes.Text = "Complete";
        }

        [Flags]
        public enum SimpleMode
        {
            None = 0,
            Simple1 = 1,
            Simple2 = 2,
            Simple3 = 4,
            Simple4 = 8,
            Simple5 = 16,
            Simple6 = 32,
        }

        private void ConfigFlightModes_Load(object sender, EventArgs e)
        {
            if (!MainV2.comPort.BaseStream.IsOpen)
            {
                this.Enabled = false;
                return;
            }
            else
            {
                this.Enabled = true;
            }

            if (MainV2.cs.firmware == MainV2.Firmwares.ArduPlane) // APM
            {
                CB_simple1.Visible = false;
                CB_simple2.Visible = false;
                CB_simple3.Visible = false;
                CB_simple4.Visible = false;
                CB_simple5.Visible = false;
                CB_simple6.Visible = false;

                CMB_fmode1.Items.Clear();
                CMB_fmode2.Items.Clear();
                CMB_fmode3.Items.Clear();
                CMB_fmode4.Items.Clear();
                CMB_fmode5.Items.Clear();
                CMB_fmode6.Items.Clear();

                CMB_fmode1.Items.AddRange(Enum.GetNames(typeof(Common.apmmodes)));
                CMB_fmode2.Items.AddRange(Enum.GetNames(typeof(Common.apmmodes)));
                CMB_fmode3.Items.AddRange(Enum.GetNames(typeof(Common.apmmodes)));
                CMB_fmode4.Items.AddRange(Enum.GetNames(typeof(Common.apmmodes)));
                CMB_fmode5.Items.AddRange(Enum.GetNames(typeof(Common.apmmodes)));
                CMB_fmode6.Items.AddRange(Enum.GetNames(typeof(Common.apmmodes)));

                try
                {
                    CMB_fmode1.Text = Enum.Parse(typeof(Common.apmmodes), MainV2.comPort.param["FLTMODE1"].ToString()).ToString();
                    CMB_fmode2.Text = Enum.Parse(typeof(Common.apmmodes), MainV2.comPort.param["FLTMODE2"].ToString()).ToString();
                    CMB_fmode3.Text = Enum.Parse(typeof(Common.apmmodes), MainV2.comPort.param["FLTMODE3"].ToString()).ToString();
                    CMB_fmode4.Text = Enum.Parse(typeof(Common.apmmodes), MainV2.comPort.param["FLTMODE4"].ToString()).ToString();
                    CMB_fmode5.Text = Enum.Parse(typeof(Common.apmmodes), MainV2.comPort.param["FLTMODE5"].ToString()).ToString();
                    CMB_fmode6.Text = Common.apmmodes.MANUAL.ToString();
                    CMB_fmode6.Enabled = false;
                }
                catch { }
            }
            if (MainV2.cs.firmware == MainV2.Firmwares.ArduCopter2) // ac2
            {
                CMB_fmode1.Items.Clear();
                CMB_fmode2.Items.Clear();
                CMB_fmode3.Items.Clear();
                CMB_fmode4.Items.Clear();
                CMB_fmode5.Items.Clear();
                CMB_fmode6.Items.Clear();

                CMB_fmode1.Items.AddRange(Enum.GetNames(typeof(Common.ac2modes)));
                CMB_fmode2.Items.AddRange(Enum.GetNames(typeof(Common.ac2modes)));
                CMB_fmode3.Items.AddRange(Enum.GetNames(typeof(Common.ac2modes)));
                CMB_fmode4.Items.AddRange(Enum.GetNames(typeof(Common.ac2modes)));
                CMB_fmode5.Items.AddRange(Enum.GetNames(typeof(Common.ac2modes)));
                CMB_fmode6.Items.AddRange(Enum.GetNames(typeof(Common.ac2modes)));

                try
                {
                    CMB_fmode1.Text = Enum.Parse(typeof(Common.ac2modes), MainV2.comPort.param["FLTMODE1"].ToString()).ToString();
                    CMB_fmode2.Text = Enum.Parse(typeof(Common.ac2modes), MainV2.comPort.param["FLTMODE2"].ToString()).ToString();
                    CMB_fmode3.Text = Enum.Parse(typeof(Common.ac2modes), MainV2.comPort.param["FLTMODE3"].ToString()).ToString();
                    CMB_fmode4.Text = Enum.Parse(typeof(Common.ac2modes), MainV2.comPort.param["FLTMODE4"].ToString()).ToString();
                    CMB_fmode5.Text = Enum.Parse(typeof(Common.ac2modes), MainV2.comPort.param["FLTMODE5"].ToString()).ToString();
                    CMB_fmode6.Text = Enum.Parse(typeof(Common.ac2modes), MainV2.comPort.param["FLTMODE6"].ToString()).ToString();
                    CMB_fmode6.Enabled = true;

                    int simple = int.Parse(MainV2.comPort.param["SIMPLE"].ToString());

                    CB_simple1.Checked = ((simple >> 0 & 1) == 1);
                    CB_simple2.Checked = ((simple >> 1 & 1) == 1);
                    CB_simple3.Checked = ((simple >> 2 & 1) == 1);
                    CB_simple4.Checked = ((simple >> 3 & 1) == 1);
                    CB_simple5.Checked = ((simple >> 4 & 1) == 1);
                    CB_simple6.Checked = ((simple >> 5 & 1) == 1);
                }
                catch { }
            }
        }
    }
}
