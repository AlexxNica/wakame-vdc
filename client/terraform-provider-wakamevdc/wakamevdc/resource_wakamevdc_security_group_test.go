package wakamevdc

import (
	"fmt"
	"testing"

	"github.com/axsh/wakame-vdc/client/go-wakamevdc"
	"github.com/hashicorp/terraform/helper/resource"
	"github.com/hashicorp/terraform/terraform"
)

const testConfigMinimal = `
resource "wakamevdc_security_group" "sg1" {
  display_name = "sg1"
}
`

func TestResourceWakamevdcSecurityGroupMinimal(t *testing.T) {
	var resourceID string

	testCheck := func(s *terraform.State) error {
		rs, _ := s.RootModule().Resources["wakamevdc_security_group.sg1"]
		if rs.Primary.ID == "" {
			return fmt.Errorf("No ID is set")
		}
		resourceID = rs.Primary.ID
		return nil
	}

	resource.Test(t, resource.TestCase{
		PreCheck:     nil,
		Providers:    testVdcProviders,
		CheckDestroy: testCheckDestroy(resourceID),
		Steps: []resource.TestStep{
			resource.TestStep{
				Config: testConfigMinimal,
				Check:  testCheck,
			},
		},
	})
}

const testConfigCreate = `
resource "wakamevdc_security_group" "sg2" {
	display_name = "sg2"
	account_id = "a-shpoolxx"
	service_type = "std"
	description = "The second group in our test"
	rules = <<EOS
tcp:22,22,ip4:0.0.0.0
icmp:-1,-1,ip4:0.0.0.0
EOS
}
`

func TestResourceWakamevdcSecurityGroupFull(t *testing.T) {
	var resourceID string

	testCreated := func(s *terraform.State) error {
		rs, secGroup, err := getTerraformResourceAndWakameSecurityGroup(s, "wakamevdc_security_group.sg2")
		if err != nil {
			return err
		}

		if secGroup.ID != rs.Primary.ID {
			return parameterCheckFailed("id", secGroup.ID, rs.Primary.ID)
		}

		return nil
	}

	resource.Test(t, resource.TestCase{
		PreCheck:     nil,
		Providers:    testVdcProviders,
		CheckDestroy: testCheckDestroy(resourceID),
		Steps: []resource.TestStep{
			resource.TestStep{
				Config: testConfigCreate,
				Check:  testCreated,
			},
		},
	})
}

//helpers
func getTerraformResourceAndWakameSecurityGroup(s *terraform.State, resourceName string) (*terraform.ResourceState, *wakamevdc.SecurityGroup, error) {
	rs, ok := s.RootModule().Resources[resourceName]
	if !ok {
		return nil, nil, fmt.Errorf("Not found: %s", resourceName)
	}

	client := testVdcProvider.Meta().(*wakamevdc.Client)
	securityGroup, _, err := client.SecurityGroup.GetByID(rs.Primary.ID)

	return rs, securityGroup, err
}

func testCheckDestroy(uuid string) resource.TestCheckFunc {
	return func(s *terraform.State) error {
		client := testVdcProvider.Meta().(*wakamevdc.Client)

		_, _, err := client.SecurityGroup.GetByID(uuid)
		if _, ok := err.(*wakamevdc.APIError); ok == false {
			return fmt.Errorf("The security group resource wasn't deleted when expected")
		}

		return nil
	}
}
