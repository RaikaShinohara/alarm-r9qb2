// SPDX-License-Identifier: GPL-2.0-only
/*
 * Route the USB data lines of a Maxim MAX77705 to the SoC.
 *
 * The MAX77705 USB-C controller (CCIC, I2C address 0x25) owns an analog switch
 * ("MUIC") in front of the USB D+/D- lines. On the Samsung Galaxy S21 FE the
 * bootloader reprograms it (MUIC CTRL1, opcode 0x06) and leaves the lines away
 * from the SoC, so the USB gadget only shows up on the host after the cable is
 * unplugged and plugged again (the CCIC firmware then re-runs detection).
 * Android's driver sets the switch back to "COM_USB" at boot; do the same here.
 *
 * CCIC mailbox, as used by Samsung's max77705_usbc driver: burst-write
 * [opcode, data...] starting at 0x21, write 0x00 to 0x41 to execute, wait for
 * UIC_INT (0x02) bit 7 (APCmdRes), then read the opcode echo at 0x51 and the
 * response from 0x52.
 */

#include <linux/bits.h>
#include <linux/delay.h>
#include <linux/i2c.h>
#include <linux/mod_devicetable.h>
#include <linux/module.h>
#include <linux/string.h>

#define MAX77705_UIC_INT		0x02
#define MAX77705_UIC_INT_APCMDRES	BIT(7)
#define MAX77705_OPCODE_WRITE		0x21
#define MAX77705_OPCODE_EXEC		0x41
#define MAX77705_OPCODE_READ		0x51

#define MAX77705_OP_CTRL1_R		0x05
#define MAX77705_OP_CTRL1_W		0x06
#define MAX77705_CTRL1_COM_USB		0x09

static int max77705_ccic_cmd(struct i2c_client *client, u8 opcode,
			     const u8 *data, int len, u8 *resp)
{
	u8 buf[8], rb[2];
	int ret, i;

	if (len > (int)sizeof(buf) - 1)
		return -EINVAL;

	buf[0] = opcode;
	if (len)
		memcpy(&buf[1], data, len);

	/* Drop a stale command-response flag */
	i2c_smbus_read_byte_data(client, MAX77705_UIC_INT);

	ret = i2c_smbus_write_i2c_block_data(client, MAX77705_OPCODE_WRITE,
					     1 + len, buf);
	if (ret)
		return ret;
	ret = i2c_smbus_write_byte_data(client, MAX77705_OPCODE_EXEC, 0);
	if (ret)
		return ret;

	for (i = 0; i < 50; i++) {
		usleep_range(2000, 3000);
		ret = i2c_smbus_read_byte_data(client, MAX77705_UIC_INT);
		if (ret < 0)
			return ret;
		if (ret & MAX77705_UIC_INT_APCMDRES)
			break;
	}
	if (i == 50)
		return -ETIMEDOUT;

	ret = i2c_smbus_read_i2c_block_data(client, MAX77705_OPCODE_READ,
					    sizeof(rb), rb);
	if (ret < 0)
		return ret;
	if (rb[0] != opcode)
		return -EIO;
	if (resp)
		*resp = rb[1];
	return 0;
}

static int max77705_usb_switch_probe(struct i2c_client *client)
{
	const u8 com_usb = MAX77705_CTRL1_COM_USB;
	u8 before = 0, after = 0;
	int ret;

	ret = max77705_ccic_cmd(client, MAX77705_OP_CTRL1_R, NULL, 0, &before);
	if (ret)
		return dev_err_probe(&client->dev, ret, "CCIC not responding\n");

	if (before != com_usb) {
		ret = max77705_ccic_cmd(client, MAX77705_OP_CTRL1_W,
					&com_usb, 1, NULL);
		if (ret)
			return dev_err_probe(&client->dev, ret,
					     "failed to set MUIC CTRL1\n");
	}

	ret = max77705_ccic_cmd(client, MAX77705_OP_CTRL1_R, NULL, 0, &after);
	if (ret)
		return dev_err_probe(&client->dev, ret, "failed to read back CTRL1\n");

	dev_info(&client->dev, "MUIC CTRL1 0x%02x -> 0x%02x (USB D+/D- to SoC)\n",
		 before, after);
	return 0;
}

static const struct of_device_id max77705_usb_switch_of_match[] = {
	{ .compatible = "maxim,max77705-usbc-usb-switch" },
	{ }
};
MODULE_DEVICE_TABLE(of, max77705_usb_switch_of_match);

static struct i2c_driver max77705_usb_switch_driver = {
	.driver = {
		.name = "max77705-usb-switch",
		.of_match_table = max77705_usb_switch_of_match,
	},
	.probe = max77705_usb_switch_probe,
};
module_i2c_driver(max77705_usb_switch_driver);

MODULE_DESCRIPTION("MAX77705 CCIC: route USB data lines to the SoC");
MODULE_LICENSE("GPL");
